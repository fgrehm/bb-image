# bb-image

Batteries included container image for running [bb](https://getbb.app), built to run rootless on your own machine with your data, logins, and projects mounted in.

## What's in it

- Debian 13 slim, pinned by digest, running as an unprivileged `developer` user (uid/gid 1000)
- Node.js, bb, and Playwright with Chromium installed at build time, so the image can serve and drive a browser without a first-run download
- A baked dev toolset: `rg`, `jq`, `fd`, `shfmt`, `shellcheck`, `tmux`, `git-lfs`, and neovim, which is aliased to `vi` and `vim` for the whole container
- The usual CLI gaps filled by apt: `ps`, `less`, `unzip`, `pkg-config`, `gpg`, `rsync`, `wget`, `file`, plus `bubblewrap` for agent sandboxing, `imagemagick` and asset tools (`cwebp`, `pngquant`, `optipng`, `jpegoptim`), and `poppler-utils` with `qpdf` for PDFs
- A UTF-8 locale (`LANG=C.UTF-8`) and `EDITOR`/`VISUAL` pointing at `vi`, so `git commit` without `-m` and `git rebase -i` work
- mise-managed toolchains, agent CLIs, and prek, installed on first use
- `$HOME` as the working directory, since bb hosts many projects and resolves them by path
- Almost nothing heavy in `$HOME` at first boot. The toolchain is at `/opt/mise` and the Playwright browsers at `/opt/ms-playwright`, so the home volume is seeded with kilobytes rather than gigabytes. Caches are the exception, and they are meant to be there: at runtime npm writes `~/.npm` and mise writes `~/.cache/mise`, both inside the home volume, so they survive a container recreate

## Lazy tool loading

The image follows Omarchy's [lazy-loading mise stubs](https://omarchy.org/manual/development-tools/): rather than baking in every toolchain, it ships mise shims and lets a tool install itself the first time you call it.

The toolset is `mise.toml` in this repo, installed into the image as the global mise config at `/opt/mise/config.toml`. Anything bb does not need in order to start is declared `lazy = true`, which makes mise generate bootstrap shims at build time. The first call to `go`, `python`, or `claude` installs that tool, then runs it.

| Installed at build time | Installed on first use |
| --- | --- |
| `node`, `bb`, `playwright` with Chromium, `neovim`, `rg`, `jq`, `fd`, `shfmt`, `shellcheck`, `tmux`, `git-lfs` | `pnpm`, `ruby`, `bun`, `go`, `rust`, `python`, `gh`, `prek`, `claude`, `codex`, `pi`, `opencode`, `grok`, `omp` |

The dev tools are baked even though they are cheap, because the toolchain is not volume-backed: a lazy copy would be re-fetched in every fresh container. The trade is that they sit at and below the layer that declares `mise.toml`, so editing the toolset re-downloads them, while node, bb, and Chromium stay cached.

`ripgrep` installs an `rg` shim and there is no `ripgrep` command. `vi` and `vim` are neovim, through small wrapper scripts in `/usr/local/bin`; they are not symlinks to the mise shim, because mise dispatches shims on `argv[0]` and a shim reached as `vim` is rejected outright.

The toolset is the global config and sits outside the home volume, so a rebuild always takes effect. Projects you mount can still pin versions with their own `mise.toml`, and `mise use -g` works inside the container too, though those changes live and die with it.

Agent CLIs and prek are deliberately unpinned, so a fresh container resolves the current release rather than whatever was current when the image was built.

Configs that use only plain version strings need no trust step; ones using `[settings]`, `[env]`, inline tables, or templated tasks do.

## Running it

```bash
make build
make run     # serves bb on http://localhost:38886
make hack    # shell in the same environment
```

bb's default port is 38886. If something else on your machine already owns it, pass another: `make run BB_PORT=39886`. It is published on `127.0.0.1` only, so it is not reachable from other machines; `make run BB_BIND=0.0.0.0` changes that, and then you should reach it by IPv4 address rather than `localhost` for the reason in the gotchas.

### The same thing without make

```bash
podman run -d --name bb \
  --userns=keep-id \
  --security-opt no-new-privileges \
  -p 127.0.0.1:38886:38886 \
  -v bb-home:/home/developer \
  -v "$HOME/src:/home/developer/src:Z" \
  bb:dev
```

`--security-opt no-new-privileges` is what `make run` and `make hack` pass. The base packages bring the standard Debian setuid binaries, including `su` and `mount`, and none of them is needed here, so this makes sure an agent cannot use them to reach container root. Drop the flag if you actually want `su` inside.

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

## Running as a microVM

[smolvm](https://smolmachines.com) boots images as libkrun microVMs with their own guest kernel. This image is consumed as-is, because a Smolfile's `image` field takes an OCI reference, a `podman save` archive, or an unpacked rootfs, so nothing needs repackaging.

`examples/smolvm/Smolfile` is a worked example. Until the first release is tagged, the pullable tag is `edge`:

```bash
smolvm machine create --name bb --smolfile examples/smolvm/Smolfile
smolvm machine start --name bb
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:38886/api/v1/hosts   # 200
smolvm machine shell --name bb
```

A local archive skips the registry pull entirely, which is the offline path and also the faster one to iterate on:

```bash
podman save ghcr.io/fgrehm/bb:edge -o bb.tar
smolvm machine create --name bb --smolfile examples/smolvm/Smolfile --image ./bb.tar
```

Verified with smolvm 1.16.0 on Linux x86_64 with KVM: the entrypoint runs as PID 1, bb answers on the published port, Playwright's Chromium launches, and state survives `machine stop` and `machine start` (0.45s and 0.71s). Three details are worth knowing before you rely on it:

- **`bwrap` works fully here**, including the fresh `/proc` mount with PID-namespace unsharing that needs `--privileged` inside a container. That limitation is a container artifact and does not apply to a VM guest.
- **Keep `net = true`, and give the machine a token.** With networking off, mise cannot resolve the unpinned agent CLIs and logs a warning on every command (`MISE_OFFLINE=1` silences those). With networking on and no token it resolves them unauthenticated instead, against a limit of 60 requests per hour, and then fails with 403s that do not read as rate limiting. smolvm resolves a `[secrets]` reference per launch, so the bridge is one line on the host, and an unset variable fails the launch loudly rather than starting unauthenticated:

  ```bash
  GH_TOKEN="$(gh auth token)" smolvm machine create --name bb --smolfile examples/smolvm/Smolfile
  ```
- **The image is `linux/amd64` only.** Matching the guest is automatic on x86_64 hosts; on Apple Silicon it needs `rosetta = true`.

The VM's disk replaces the container's named volume: `~/.bb`, caches, and shell state live on the machine's storage disk and persist across `exec` and restarts, with no seed-on-first-boot semantics to reason about.

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
- Keep anything the image owns out of `$HOME`. Home is volume-backed, so a file placed there freezes at first boot and shadows later image updates. That is why the toolset, mise's data dir, and Playwright's browsers are all under `/opt`. Caches are the deliberate exception: nothing in the image pins a cache location, so runtime caches land in the home volume and persist, while build-time caches go to `/tmp` and are removed inside the same `RUN`, because a delete in a later layer reclaims nothing.
- Only small tools are left to first use. Since the toolchain lives in the image rather than a volume, a runtime-installed tool is gone once the container is recreated and is re-fetched on next use. The dev tools are the exception: they are baked because they are used constantly, so the re-fetch would happen in every fresh container.
- A login shell keeps the lazy tools. Debian's `/etc/profile` resets `PATH` outright, which used to drop the mise shims and make every lazy tool "command not found" under `bash -l`. `/etc/profile.d/mise-shims.sh` puts them back. zsh never had the problem, since `/etc/zsh/zshenv` only sets `PATH` when it is empty.
- `bwrap` is installed for agent sandboxing: Claude Code's bash sandbox shells out to it, and bb's own reference sandbox image installs it first. It is not setuid, and it runs unprivileged because podman's default seccomp permits user namespaces under `--userns=keep-id`.
- `make run` publishes bb on `127.0.0.1` only, via `BB_BIND`. That is deliberate: a wildcard publish makes pasta listen dual-stack, and on this podman and pasta (`6.1.1` with `2026_07_28.f8df3f1`) IPv6 connections are reset while IPv4 works. Since `localhost` resolves to `::1` first, clients fail rather than falling back, so `http://localhost:38886` looks broken even though the port is fine. Bound to `127.0.0.1` there is no IPv6 listener and `localhost` works. Set `BB_BIND=0.0.0.0` to expose bb on the LAN, then use the IPv4 address. `--network=host` is the fallback if a rootless networking setup misbehaves in some other way.
- `--security-opt no-new-privileges` is set by `make run` and `make hack`. The image inherits the usual Debian setuid binaries from its base packages (`su`, `mount`, `passwd`, `chsh`, `chfn`, `gpasswd`, `newgrp`, `umount`, and openssh's `ssh-keysign`) and none of them serves this image's purpose, so `NO_NEW_PRIVS` makes setuid and file capabilities unable to elevate. Verified: `/proc/self/status` reports `NoNewPrivs: 1`, bubblewrap still works because creating a namespace is not a privilege gain, and bb starts and stops cleanly. It is a run-behaviour change, so it counts as a major bump if you are versioning this image.
- One sandbox limitation is unavoidable inside a container. Mounting a fresh `/proc` together with PID-namespace unsharing fails with `Can't mount proc on /proc: Operation not permitted`, and `--privileged` is the only thing measured to lift it. `seccomp=unconfined`, `apparmor=unconfined`, `label=disable` and `--cap-add SYS_ADMIN` do not help, and bwrap refuses to start with extra capabilities anyway (`Unexpected capabilities but not setuid`). Workarounds that do work: reuse the parent's `/proc` with `--ro-bind /proc /proc`, or drop the PID namespace. `make run` deliberately does not pass `--privileged`.
- `pnpm` is on hand for projects that want it, and it is lazy, since bb itself never uses it: bb detects package managers only to report them and installs its plugins with npm. The store lives at `~/.local/share/pnpm/store`, inside the home volume, so repeat installs are fast and survive a container recreate. Projects that hard-link from the host are the exception, since a bind mount is a different filesystem and pnpm falls back to copying. pnpm 10 and later also refuse to run dependency lifecycle scripts unless they are allow-listed, so a native dependency can install cleanly and still be broken; `pnpm approve-builds` fixes it.
- `magick`, `convert`, `identify`, `mogrify`, `compare` and `montage` are ImageMagick 7, and it is what the MiniMagick Ruby gem shells out to, so having it covers both. `--no-install-recommends` keeps it near 23MB and skips the delegate zoo, which has one consequence worth knowing: reading PDF or PostScript needs the ghostscript delegate, which is not installed. Writing a simple PDF works, reading one back does not. Debian's `policy.xml` also disables the URL, HTTP and HTTPS coders, so ImageMagick will not fetch a remote image for you; download it first. For PDFs use poppler instead: `pdftotext`, `pdftoppm` and `pdfinfo` read them without ghostscript, and `qpdf` handles structure, repair and linearising.
- `LANG` is `C.UTF-8` rather than unset, so non-ASCII in Ruby, `git log`, and tool output behaves. `EDITOR` and `VISUAL` both point at `vi`, which is neovim.
- Playwright's browsers are pre-downloaded to `/opt/ms-playwright`, and `PLAYWRIGHT_BROWSERS_PATH` points there, so a project only needs the `playwright` package to use them.
- `minimum_release_age` is unset, which is what lets the unpinned agent CLIs resolve to the newest release. Enabling it would hold them back; Omarchy zeroes it per invocation (`MISE_MINIMUM_RELEASE_AGE=0`) for the same reason.
- `node` is pinned by `NODE_VERSION` in the `Containerfile` as well as in `mise.toml`. That duplication is what keeps a toolset edit from rebuilding the node and bb layers, and the build fails if the two disagree.
- Bumping the node version means reinstalling bb, since bb lives inside mise's node install.
