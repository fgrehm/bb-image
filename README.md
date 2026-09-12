# bb-image

Batteries included container image for running [bb](https://getbb.app), built to run rootless on your own machine with your data, logins, and projects mounted in.

## What's in it

- Debian 13 slim, pinned by digest, running as an unprivileged `developer` user (uid/gid 1000)
- Node.js and bb installed at build time, so the image is ready to serve
- mise-managed toolchains and agent CLIs, installed on first use
- `$HOME` as the working directory, since bb hosts many projects and resolves them by path

## Lazy tool loading

The image follows Omarchy's [lazy-loading mise stubs](https://omarchy.org/manual/development-tools/): rather than baking in every toolchain, it ships mise shims and lets a tool install itself the first time you call it.

The toolset is `mise.toml` in this repo, installed into the image as the global mise config at `~/.config/mise/config.toml`. Anything bb does not need in order to start is declared `lazy = true`, which makes mise generate bootstrap shims at build time. The first call to `go`, `python`, or `claude` installs that tool, then runs it.

| Installed at build time | Installed on first use |
| --- | --- |
| `node`, `bb` | `ruby`, `bun`, `go`, `rust`, `python`, `gh`, `claude`, `codex`, `pi`, `opencode`, `grok`, `omp` |

Because the toolset is the *global* config, projects you mount can still pin their own versions with a project `mise.toml`. Configs that use only plain version strings need no trust step; ones using `[settings]`, `[env]`, inline tables, or templated tasks do.

Agent CLIs are deliberately unpinned, so a fresh container resolves the current release rather than whatever was current when the image was built.

## Running it

```bash
make build
make run     # serves bb on http://localhost:38886
make hack    # shell in the same environment
```

bb's default port is 38886. If something else on your machine already owns it, pass another: `make run BB_PORT=39886`.

### The same thing without make

```bash
podman run -d --name bb \
  --userns=keep-id \
  -p 38886:38886 \
  -v bb-state:/home/developer/.bb \
  -v bb-mise:/home/developer/.local/share/mise \
  -v "$HOME/src:/home/developer/src:Z" \
  bb:dev
```

`--userns=keep-id` is not optional in practice. Rootless podman maps container uid 1000 to a subordinate uid by default, so anything the container writes to a bind mount lands owned by a subuid and you cannot touch it on the host. `keep-id` maps it back to your own uid, and files come out owned by you.

On Docker, `--userns=keep-id` does not exist. Rootful Docker already writes bind mounts as uid 1000, which is your user on most single-user Linux installs. With rootless Docker, check what your files look like before trusting it.

### What persists, and what does not

| Mount | Holds | If you leave it out |
| --- | --- | --- |
| `bb-state:/home/developer/.bb` | Threads, projects, settings, auth secret | Every container starts empty |
| `bb-mise:/home/developer/.local/share/mise` | Installed toolchains and shims | Every new container reinstalls tools |
| `~/src:/home/developer/src` | Your code | bb has nothing to work on |
| `bb-home` style mounts | Whatever else you want to keep | That data dies with the container |

Use named volumes for the two container-owned directories. Both are seeded from the image the first time they are created, which is what puts the baked shims and node into the mise volume. Pointing either at an empty bind mount leaves the container with no tools on `PATH`.

### Sharing your host logins and identity

Nothing outside those two volumes persists by default, so agent CLI logins have to be mounted in or repeated on every new container. Reusing the host's is usually less work, and means one login serves both:

```bash
make run MOUNTS='-v ~/.config/git:/home/developer/.config/git \
                 -v ~/.ssh:/home/developer/.ssh \
                 -v ~/.claude:/home/developer/.claude \
                 -v ~/.claude.json:/home/developer/.claude.json \
                 -v ~/.codex:/home/developer/.codex \
                 -v ~/.config/gh:/home/developer/.config/gh \
                 -v ~/.pi:/home/developer/.pi \
                 -v ~/.omp:/home/developer/.omp'
```

Mounting the host's agent config means the container's CLI version writes state that your host CLI also reads. That is normally fine and occasionally not, so if a provider starts misbehaving, drop its mount and log in inside the container instead.

## Publishing

`.github/workflows/publish.yml` builds and pushes on every push to `main` and on `v*` tags. There are two version axes: the bb release baked into the image, read from `BB_VERSION` in the Containerfile so a tag can never disagree with what is inside, and the image's own version, taken from the git tag. The second exists so that an image-only change, such as a node bump or a refreshed base digest, has somewhere to go without a bb release.

`make release VERSION=0.1.0` tags and pushes, which is what runs the workflow. The tag message records the bb version, so `git tag -n1` answers which bb is in which image without opening the Containerfile.

| Ref | Tags |
| --- | --- |
| `main` | `edge` |
| `v0.1.0` with `BB_VERSION=0.43.1` | `0.43.1`, `0.43`, `img-0.1.0`, `latest` |
| `v0.3.0-rc1` | `img-0.3.0-rc1` only |

So `ghcr.io/fgrehm/bb:0.43.1` is the image for bb 0.43.1, while `:img-0.1.0` pins that exact image build.

The bb tags follow the newest image for that bb release, so a node bump or a base digest refresh republishes them and anyone on `:0.43.1` picks the fix up. Pin `:img-<version>` when you want one specific build rather than one specific bb release. A prerelease tag publishes the `img-` tag and nothing else, so an rc cannot move the bb aliases or `latest`.

It publishes to GHCR as `ghcr.io/fgrehm/bb` using the built-in `GITHUB_TOKEN`, so there are no secrets to configure. That name is set by `IMAGE_NAME` in the workflow; it does not follow the repo name, which is `bb-image`.

For Docker Hub, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets, change the login step to `docker/login-action` with `registry: docker.io` and those credentials, and change `IMAGE_NAME`.

The image is built for `linux/amd64` only. `linux/arm64` is untested: `node-pty` and `better-sqlite3` fall back to `node-gyp` when no prebuild matches, and that needs `python3` at build time, which the image deliberately does not carry at that stage. Add `linux/arm64` to `PLATFORMS` only after verifying a build.

## Gotchas

- First-use installs write progress to stderr and never to stdout, so captured tool output stays clean. Without a TTY, as for anything bb spawns, mise degrades to plain text lines with no ANSI escapes and no carriage-return redraws. `MISE_QUIET=1` silences it entirely.
- bb sends service output to `~/.bb/logs/*` and never to the terminal. The entrypoint runs bb behind a small init that tails both log files, so `make run` and `podman logs bb` both show them.
- `make run` and `make hack` share the same volumes, so a CLI you install or log into in the shell is visible to the server.
- Bumping a pinned version in `mise.toml` leaves the old install in the mise volume and downloads the new one on first use. `podman volume rm bb-mise` reclaims it.
- The mise volume's shim farm is a snapshot from when that volume was created, and it shadows the image's. The entrypoint runs `mise reshim` on every start to reconcile it. Without that, a tool added to a rebuilt image installs correctly but has no shim, so there is no way to invoke it and you get `command not found` for something that is genuinely installed.
- `minimum_release_age` is unset, which is what lets the unpinned agent CLIs resolve to the newest release. Enabling it would hold them back; Omarchy zeroes it per invocation (`MISE_MINIMUM_RELEASE_AGE=0`) for the same reason.
- `node` is pinned by `NODE_VERSION` in the `Containerfile` as well as in `mise.toml`. That duplication is what keeps a toolset edit from rebuilding the node and bb layers, and the build fails if the two disagree.
- Bumping the node version means reinstalling bb, since bb lives inside mise's node install.
