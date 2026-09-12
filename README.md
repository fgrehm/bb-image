# bb-image

Batteries included container image for running [bb](https://getbb.app), built to run rootless on your own machine with your data, logins, and projects mounted in.

## What's in it

- Debian 13 slim, pinned by digest, running as an unprivileged `developer` user (uid/gid 1000)
- Node.js, bb, and Playwright with Chromium installed at build time, so the image can serve and drive a browser without a first-run download
- mise-managed toolchains, agent CLIs, and prek, installed on first use
- `$HOME` as the working directory, since bb hosts many projects and resolves them by path
- Almost nothing heavy in `$HOME`. The toolchain is at `/opt/mise`, the Playwright browsers at `/opt/ms-playwright`, and the npm cache at `/opt/npm-cache`, all outside the home volume so first boot copies kilobytes rather than gigabytes into it

## Lazy tool loading

The image follows Omarchy's [lazy-loading mise stubs](https://omarchy.org/manual/development-tools/): rather than baking in every toolchain, it ships mise shims and lets a tool install itself the first time you call it.

The toolset is `mise.toml` in this repo, installed into the image as the global mise config at `/opt/mise/config.toml`. Anything bb does not need in order to start is declared `lazy = true`, which makes mise generate bootstrap shims at build time. The first call to `go`, `python`, or `claude` installs that tool, then runs it.

| Installed at build time | Installed on first use |
| --- | --- |
| `node`, `bb`, `playwright` with Chromium | `ruby`, `bun`, `go`, `rust`, `python`, `gh`, `prek`, `claude`, `codex`, `pi`, `opencode`, `grok`, `omp` |

The toolset is the global config and sits outside the home volume, so a rebuild always takes effect. Projects you mount can still pin versions with their own `mise.toml`, and `mise use -g` works inside the container too, though those changes live and die with it.

Agent CLIs and prek are deliberately unpinned, so a fresh container resolves the current release rather than whatever was current when the image was built.

Configs that use only plain version strings need no trust step; ones using `[settings]`, `[env]`, inline tables, or templated tasks do.

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
  -v bb-home:/home/developer \
  -v "$HOME/src:/home/developer/src:Z" \
  bb:dev
```

`--userns=keep-id` is not optional in practice. Rootless podman maps container uid 1000 to a subordinate uid by default, so anything the container writes to a bind mount lands owned by a subuid and you cannot touch it on the host. `keep-id` maps it back to your own uid, and files come out owned by you.

On Docker, `--userns=keep-id` does not exist. Rootful Docker already writes bind mounts as uid 1000, which is your user on most single-user Linux installs. With rootless Docker, check what your files look like before trusting it.

### What persists

One volume covers everything worth keeping: threads, projects, settings, the auth secret, provider logins, git config, ssh keys, and shell history. It is seeded from the image on first creation, which is where `~/.bb` and the shell config come from, and it stays small because nothing heavy lives in `$HOME`.

| Mount | Holds | If you leave it out |
| --- | --- | --- |
| `bb-home:/home/developer` | bb state, provider logins, git and ssh config, history | All of it dies with the container and you re-login to every provider |
| `~/src:/home/developer/src` | Your code | bb has nothing to work on |

The toolchain is deliberately *not* on a volume. It lives in the image at `/opt/mise`, so it stays in step with the image instead of freezing at volume creation. The trade is that tools installed at runtime are per-container and re-fetched after a rebuild, which is why only cheap ones are left to first use.

### Reusing logins you already have on the host

Not required, since the home volume keeps its own logins. But if you would rather not sign in twice, mount the host's:

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
- `make run` and `make hack` share the same volume, so a CLI you install or log into in the shell is visible to the server.
- The toolset has to be the *global* mise config, which is what `MISE_GLOBAL_CONFIG_FILE` points at. Moving it to the system config at `/etc/mise` looks tidier and reads identically, but mise only creates bootstrap shims for tools from the user and project scope, so every lazy tool would silently lose its shim and first-use installation would stop working.
- Keep anything the image owns out of `$HOME`. Home is volume-backed, so a file placed there freezes at first boot and shadows later image updates. That is why the toolset, mise's data dir, Playwright's browsers, and the npm cache are all under `/opt`.
- Only small tools are left to first use. Since the toolchain lives in the image rather than a volume, a runtime-installed tool is gone once the container is recreated and is re-fetched on next use.
- Playwright's browsers are pre-downloaded to `/opt/ms-playwright`, and `PLAYWRIGHT_BROWSERS_PATH` points there, so a project only needs the `playwright` package to use them.
- `minimum_release_age` is unset, which is what lets the unpinned agent CLIs resolve to the newest release. Enabling it would hold them back; Omarchy zeroes it per invocation (`MISE_MINIMUM_RELEASE_AGE=0`) for the same reason.
- `node` is pinned by `NODE_VERSION` in the `Containerfile` as well as in `mise.toml`. That duplication is what keeps a toolset edit from rebuilding the node and bb layers, and the build fails if the two disagree.
- Bumping the node version means reinstalling bb, since bb lives inside mise's node install.
