# bb-image

Batteries included container image for running [bb](https://getbb.app), built to run rootless on your own machine with your data, logins, and projects mounted in.

## Variants

| Tags | What it carries | For |
| --- | --- | --- |
| `ghcr.io/fgrehm/bb` (also `full`, `latest`, the bb-version tags, and `img-<v>` pins) | Everything in [What's in the full image](#whats-in-the-full-image): Playwright + Chromium, dev tools, DB clients, document tools, backup tooling | The default bb server |
| `ghcr.io/fgrehm/bb:slim` and version pins like `img-<v>-slim`, `0.43.3-slim` | Debian, node, bb, mise, lazy `pnpm` + agent CLIs. No Chromium, dev tools, DB clients, document tools, compilers, or sudo. ~925MB vs ~2,398MB | A small bb runtime you size up yourself |
| `ghcr.io/fgrehm/bb:0.43.3-slim-sudo` with `edge-slim-sudo` and `img-<v>-slim-sudo` moving alongside | slim plus passwordless sudo | Assembling an environment interactively |
| `ghcr.io/fgrehm/bb:0.43.3-full-sudo` with `edge-full-sudo` and `img-<v>-full-sudo` moving alongside | the default image plus passwordless sudo | Long-lived development containers; also the bb-source contributor environment |

The moving aliases are `latest` (which means full) and bare `slim`; the sudo flavors deliberately have no bare alias and are reached through their suffix pins, of which the three forms are `edge-<variant>` (the current `main` build), `0.43.3-<variant>` (the current baked bb), and `img-<version>-<variant>` (a frozen release by the image's own version).

Versioned tags carry a variant suffix (`0.43.3-slim`, `img-0.3.0-full-sudo`); the unsuffixed tags always mean `full`. Internally the container has sudo only: apt packages and mise tools installed at runtime live with the container and vanish when a disposable one stops, so sudo flavors want a named home volume and a non-`--rm` run.

The unsuffixed `latest`, `edge`, and bb-version tags stay on the full image; nothing about those tags changes. The full and slim non-sudo images keep the `no-new-privileges` security flag (`make run` and `make hack` set it), and the `-sudo` flavors are run without it (the Makefile derives it) because passwordless sudo depends on setuid. Choosing a sudo flavor means choosing that posture: the container itself is still rootless, but give it nothing you mind it owning (no host ssh keys mount, no podman socket, no broad host paths).

## What's in the full image

- Debian 13 slim, pinned by digest, running as an unprivileged `developer` user (uid/gid 1000)
- Node.js, bb, and Playwright with Chromium installed at build time, so the image can serve and drive a browser without a first-run download
- A baked dev toolset: `rg`, `jq`, `fd`, `shfmt`, `shellcheck`, `tmux`, `git-lfs`, and neovim, which is aliased to `vi` and `vim` for the whole container
- The usual CLI gaps filled by apt: `ps`, `less`, `unzip`, `pkg-config`, `gpg`, `rsync`, `wget`, `file`, plus `bubblewrap` for agent sandboxing, `imagemagick` and asset tools (`cwebp`, `pngquant`, `optipng`, `jpegoptim`), `poppler-utils` with `qpdf` for PDFs, and `zstd` for compressed backups
- `bb-backup`, a baked backup script with three subcommands: `backup` tars the persistent state to a zstd archive, snapshots live SQLite databases (`~/.bb/bb.db` and friends) with `sqlite3 .backup` so the archive holds a consistent copy, verifies the archive with `zstd -t` and a full `tar -tf` pass before it is named, and prunes by retention; `traces` mirrors agent session traces and logs (pi sessions, bb logs, the pi bridge, claude, codex) into a directory with rsync, additively and never pruning; `verify` re-runs the integrity check. See [Backups](#backups)
- A UTF-8 locale (`LANG=C.UTF-8`) and `EDITOR`/`VISUAL` pointing at `vi`, so `git commit` without `-m` and `git rebase -i` work
- mise-managed toolchains, agent CLIs, and prek, installed on first use
- `$HOME` as the working directory, since bb hosts many projects and resolves them by path
- A container-level `~/.bb/AGENTS.md` that bb appends to the system prompt of every provider-backed thread, telling agents how the mise toolchain works (lazy installs, project pins, the `/opt/mise` ownership rule, and that what is baked varies by image flavor: check before assuming a tool is there). Edits you make to your copy are kept; unmodified copies are kept current
- Home hydration: `~/.bb/AGENTS.md` and the `mise activate` blocks in `~/.bashrc` and `~/.zshrc` are image-managed, and a named volume is seeded from the image only once, so the entrypoint hydrates them on every container start. A copy the image shipped (recognised by hash) is replaced when the image moves on; a copy you edited is left untouched
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

Project pins resolve with no shell setup, interactive or not: a shim reads the repo's `mise.toml` each time it is invoked, so a git hook or anything else bb spawns gets the project's tools. Whichever version resolves installs into `/opt/mise/installs/<tool>/<version>`, versioned and side by side, so two projects pinning different versions do not disturb each other. The consequence is that `/opt/mise` has to stay writable at runtime, including inside a sandbox: if a sandbox denies it, the first use of a project-pinned tool fails with a permission error instead of falling back. Allow writes to `/opt/mise`, or bind a per-project directory over `/opt/mise/installs`.

Agent CLIs and prek are deliberately unpinned, so a fresh container resolves the current release rather than whatever was current when the image was built.

Configs that use only plain version strings need no trust step; ones using `[settings]`, `[env]`, inline tables, or templated tasks do.

## Home hydration

The `~/.bb/AGENTS.md` guidance and the `mise activate` blocks in `~/.bashrc` and `~/.zshrc` live in the home volume, and a named volume is seeded from the image exactly once. Left alone, a volume would carry its first-boot copies forever, so the entrypoint hydrates them on every container start.

The mechanism is hash-based. The image ships the pristine sources and a registry at `/usr/local/share/bb` (outside the volume), and the entrypoint runs `hydrate-home.sh install` before bb starts. A home copy whose hash matches a hash the image has shipped is ours and gets replaced when the content moves on, one version or several; a copy whose hash matches nothing the image has shipped is assumed to be user-edited and is left untouched. A hash you do not recognise is therefore a permanent opt-out, and the hydrator logs which of the three happened on each start.

Editing your copy in the volume is supported and is the intended way to fine-tune it. Two consequences worth knowing: the user edit wins, meaning you silently stop receiving updates for that file, and the only escape is deleting the file, or the whole managed block with both markers, so the image reinstalls it.

## Running it

```bash
make build
make run     # serves bb on http://localhost:38886
make hack    # shell in the same environment
make check   # verify the built image
make ci      # build + verify in one target (what release CI runs)
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

## Developing bb itself

`full-sudo` is the contributor environment: a packaged bb runs its server while the source-built bb runs beside it with its own data and ports. No bb source is baked into any image; the checkout stays wherever you cloned the fork and is mounted in.

```bash
make ci FLAVOR=full-sudo TAG=full-sudo
# Exported, not an argument: the value stays out of podman's argv and any
# process list on the host.
export MISE_GITHUB_TOKEN
MISE_GITHUB_TOKEN="$(gh auth token 2>/dev/null)"
podman run -d --name bb-dev \
	--userns=keep-id \
	--env MISE_GITHUB_TOKEN \
	-v ~/src/bb:/home/developer/src:Z \
	-v bb-dev-home:/home/developer \
	ghcr.io/fgrehm/bb:img-<version>-full-sudo sleep infinity
podman exec -it bb-dev bash
```

Inside the container, from the checkout:

1. `mise install python pnpm` — one-time. `pnpm` works lazy, but node-gyp resolves `python3` on PATH, which is mise's lazy shim, so a fast python has to be installed into mise first. Mise needs a `GITHUB_TOKEN` in the environment for first-use installs on a rate-limited IP; no scopes are required.
2. `pnpm install` — the checkout's `packageManager` field (pnpm@9.15.0 today) is authoritative; the native modules (better-sqlite3, node-pty, @parcel/watcher) compile against the image's build toolchain.
3. `pnpm dev` for the development loop, or `pnpm start:worktree` to exercise the production-style serving path. Each checkout gets its own data directory under `~/.bb-dev/<checkout-instance>/` and deterministic high ports derived from the checkout path, so it runs alongside a packaged bb instance without touching its state. The launcher prints its ports.

Sudo matters here because the vendor agents and package installs inside the checkout may want apt packages; the container is still rootless, so host access stays bounded by the container itself.

There is no separate `bb:source` variant. `full-sudo` was proven against a real checkout (install, native compile, dev boot) and the smaller focused image would duplicate its build prerequisites without saving anything that matters.

## Backups

`/usr/local/share/bb/bb-backup` has three subcommands and no default: `backup` (the recovery archive), `traces` (the additive mirror), and `verify`. A bare `bb-backup` prints usage. It does not schedule anything: the image is rootless and ships no boot-time service, so the timer lives wherever the container is run from (a host systemd user timer, a Quadlet, or a compose sidecar cron) and calls this script.

### Recovery archive

```bash
bb-backup backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

That writes `/backups/backup-<timestamp>.tar.zst`, snapshotting the live bb database (only for the `--sqlite` paths you name; the sources are copied as-is otherwise) so the archive is not a mid-write mix of pages, keeping the 7 newest archives, and pruning the rest. Every archive is verified before it is named: the zstd stream is tested (`zstd -t`) and the tar payload is listed end to end (`tar -tf`), so a truncated or corrupt archive exits nonzero and never lands under the canonical name. `bb-backup verify FILE` re-runs that check for restore flows.

Restore is plain tar: unpack the archive over a fresh home, then recreate the container with that volume. The sqlite snapshot unpacks to its real path and replaces the live database's copy.

To run it from the host, bind the output directory and the state you are archiving:

```bash
podman run --rm -v bb-home:/home/developer:ro -v /var/backups/bb:/backups \
    ghcr.io/fgrehm/bb /usr/local/share/bb/bb-backup \
    backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

The read-only mount keeps bb free to serve while the archive runs; the sqlite snapshot covers the one file that would otherwise be mid-write. For a scheduled setup, wrap that command in a systemd user timer with `Persistent=true`, so missed runs are caught up after a reboot.

### Trace archival

`bb-backup traces` mirrors agent session traces and logs into a directory with rsync, additively and independently of bb: pi sessions (`~/.pi/agent/sessions`), bb logs (`~/.bb/logs`), the pi bridge (`~/.bb/pi-bridge-sessions`), and claude and codex state (`~/.claude`, `~/.codex`) are included by default when they exist. Locations a deployment always wants can be baked into the environment with `BB_BACKUP_TRACES_INCLUDES` (colon-separated, like `PATH`, missing entries skipped), so a compose file or timer unit carries the convention without flags; `--include PATH` adds paths on top and must exist. It never prunes and never deletes: each run copies only the files modified since the previous run (tracked by a `.traces-last` marker in the output directory, with nanosecond precision so nothing at the boundary is missed), and a file the source later removes stays in the mirror. The directory accumulates every trace the CLIs ever wrote.

Two layouts, chosen with a flag. The default preserves full source paths in the mirror (`/traces/home/developer/.bb/logs/server.log`). `--flatten` merges every source into the target instead, structure below each include preserved — the shape a manual `rsync -av src/* dest/` produces. That is what a synced remote usually wants, one directory per tool rather than one per machine or container:

```bash
bb-backup traces --output /mnt/traces/this-host/pi --flatten \
    --include ~/.pi/agent/sessions \
    --include ~/.local/share/pairoot/home/.pi/agent/sessions
bb-backup traces --output /mnt/traces/this-host/bb --flatten \
    --include ~/.bb/pi-bridge-sessions \
    --include ~/.local/share/pairoot/home/.bb/pi-bridge-sessions
bb-backup traces --output /mnt/traces/work/claude --flatten \
    --include ~/.claude/projects \
    --include ~/Work/devpod-data/claude/projects \
    --include ~/Work/smol-data/claude/projects
```

Flatten mode merges by relative path, so two sources holding the same relative path overwrite each other (last write wins, nothing removed). In practice that is rare: session traces are UUID- and thread-id-named, so distinct sources almost never hold the same name. Traces are plain files in the mirror, not an archive: read them directly, or rsync the mirror wherever you keep history. rsync's exit status is the integrity check, and a failed run leaves the marker unmoved, so the next run picks up the same files. Run it from a timer as often as you like; empty runs write nothing.

## Using this image as a base

The image is meant to be layered on. `/opt/mise`, the mise data dir, is owned by and writable by `developer`, so a derived image can add tools with `mise install` or `npm install -g` and they behave like the baked ones.

Run those as `developer`, which is the image's default user. If a `Containerfile` needs `USER root` for `apt-get`, a `chmod` or a `chown`, switch back with `USER developer` before any install:

```dockerfile
FROM ghcr.io/fgrehm/bb:0.43.3

USER root
RUN apt-get update && apt-get install -y --no-install-recommends your-tool \
    && rm -rf /var/lib/apt/lists/*

USER developer
RUN mise install <tool> && mise reshim --force
```

A `mise install` run as `root` writes root-owned directories under `/opt/mise`, and `developer` cannot add versions to them afterwards. There is no permission fix for that which survives the image build, so keep installs as `developer`. The build asserts the `/opt/mise` ownership invariant, so a regression on the base side fails before it ships. That invariant also has to hold at runtime: anything that sandboxes an agent, whether a derived image or an external layer, must leave `/opt/mise` writable, or first-use installs of project pins fail there. See the gotchas for why there is no shell-hook workaround.

To replace the baked toolset rather than extend it, point `MISE_GLOBAL_CONFIG_FILE` at your own file. That replaces the global config at `/opt/mise/config.toml`; the two are not merged. Pin versions there when the derived image has to work without the network:

```dockerfile
COPY --chown=developer:developer my-tools.toml /opt/my-tools.toml
ENV MISE_GLOBAL_CONFIG_FILE=/opt/my-tools.toml
USER developer
RUN mise install && mise reshim --force
```

Pinning is what removes the network round trip: a pinned version that is already installed runs offline. `MISE_OFFLINE=1` goes further and blocks HTTP entirely, turning a missing tool into a hard failure at the point of use. `MISE_LOCKED=1` with a `mise lock` lockfile does the same for `mise install`. Neither silences the resolution warnings for any unpinned `latest` tools left in the config, so pin or drop those as well if the derived image has to be quiet and fully offline. If unpinned agent CLIs (`claude`, `codex`, ...) emit rate-limit warnings when a tokenless build resolves them, `MISE_GITHUB_TOKEN` in the environment is the quiet path; the base build keeps them unpinned on purpose so a fresh container resolves the current release. The baked config gives version fetches 15 seconds and caches the catalog for a day (`fetch_remote_versions_timeout`, `fetch_remote_versions_cache`) — but a shim invocation itself is capped by mise at ~3s no matter what, so a slow resolution falls back silently and warns; only a direct `mise install` inherits the wider window.

### Contracts a derived image can rely on

- **Identity marker.** Every variant stamps an `sh.bb.flavor` OCI label, and the check harness refuses to run an image's checks under another flavor's marker. Derived images keep the label inherited from the base stage they build from; re-stamp only when your derivation changes the contract enough to matter to you. The upstream CI treats the label as identity, so it is a stable contract by design.
- **The baked entrypoint is optional.** It does three things: hydrate the image-managed home files, mirror bb's log files to stdout, and run bb with SIGTERM forwarding for a clean stop. A derived image that overrides `ENTRYPOINT` silently skips the hydration and the log mirroring (bb writes its service output to files and never to stdout). Two softeners: the image home is pre-hydrated at build time, so a NEW home volume seeded from the image carries the managed rc blocks even if hydration never re-runs; and the only content hydration is there to *update* is the files whose hashes the image has shipped (`managed.tsv`). If your derived image overrides the entrypoint, hydration versions stop ticking on your volumes — either chain to `/home/developer/entrypoint.sh` from your own script, or accept that trade deliberately.
- **The hydration registry has no username in it.** Managed targets are `.bb/AGENTS.md`, `.bashrc`, `.zshrc` — home-relative paths. Renaming the image user (`usermod -l <new> -d <new home> -m developer`) therefore does not corrupt it; ownership is by uid 1000, so the baked content and the check invariants move with the rename. This is an upstream invariant worth keeping, and it is why the rename pattern in `AGENTS.md` ("Using this image as a base") keeps working across digests.
- **Cache and data paths are declared twice, on purpose.** The global mise config declares `npm_config_cache`, the pnpm store-dir (both `pnpm_config_*` and `npm_config_*` prefixes, so repo-pinned pnpm 9.x through 12.x land the same way), `CARGO_HOME`, `GOPATH`/`GOMODCACHE`/`GOCACHE`, and `UV_CACHE_DIR` — and the image bakes the same keys as plain ENV so they hold for any exec context, shell or not. The mise copies are `{{ env.HOME }}`-relative and resolved per container, so a derived image that renames the user keeps correct paths inside mise-managed shells and shim invocations (the ENV copies keep the baked default home and are wrong there; redeclare them if you need them outside mise after a rename — pAIr00t's compose does exactly that). The point is predictability for sandbox policies: every path is checkable config, not per-tool probe noise (pnpm#9246 is the canonical nuisance). Add your own with `mise use` and the same ENV pattern.

If your derived image overrides `ENTRYPOINT`, `bb-app` alone is a complete replacement: hydration is the entrypoint's only state-mutating step, and the log mirroring is a convenience, not plumbing bb needs. `~/.bb/logs/*` files still show up wherever the derived image points at them.

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

`.github/workflows/publish.yml` builds on every push to `main` and on `v*` tags, runs `make check` against the built image, and only then pushes to GHCR, so a failing check blocks every publish. A `main` push that only touches documentation, meaning markdown, `examples/`, `LICENSE` or `.gitignore`, skips the build entirely, since none of it reaches the image. Tag pushes are never filtered, so a release always builds even when the tagged commit is documentation-only. There are two version axes: the bb release baked into the image, read from `BB_VERSION` in the Containerfile so a tag can never disagree with what is inside, and the image's own version, taken from the git tag. The second exists so that an image-only change, such as a node bump or a refreshed base digest, has somewhere to go without a bb release.

`make release VERSION=0.1.0` tags and pushes, which is what runs the workflow. The tag message records the bb version, so `git tag -n1` answers which bb is in which image without opening the Containerfile.

| Ref | Tags |
| --- | --- |
| `main` | `edge` |
| `v0.1.0` with `BB_VERSION=0.43.1` | `0.43.1`, `0.43`, `img-0.1.0`, `latest` |
| `v0.3.0-rc1` | `img-0.3.0-rc1` only |

So `ghcr.io/fgrehm/bb:0.43.1` is the image for bb 0.43.1, while `:img-0.1.0` pins that exact image build.

The bb tags follow the newest image for that bb release, so a node bump or a base digest refresh republishes them and anyone on `:0.43.3` picks the fix up. Pin `:img-<version>` when you want one specific build rather than one specific bb release. A prerelease tag publishes the `img-` tag and nothing else, so an rc cannot move the bb aliases or `latest`.

It publishes to GHCR as `ghcr.io/fgrehm/bb` using the built-in `GITHUB_TOKEN`, so there are no secrets to configure. That name is set by `IMAGE_NAME` in the workflow; it does not follow the repo name, which is `bb-image`.

For Docker Hub, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets, change the login step to `docker/login-action` with `registry: docker.io` and those credentials, and change `IMAGE_NAME`.

The image is built for `linux/amd64` only. `linux/arm64` is untested: `node-pty` and `better-sqlite3` fall back to `node-gyp` when no prebuild matches, and that needs `python3` at build time, which the image deliberately does not carry at that stage. Add `linux/arm64` to `PLATFORMS` only after verifying a build.

## Gotchas

- First-use installs write progress to stderr and never to stdout, so captured tool output stays clean. Without a TTY, as for anything bb spawns, mise degrades to plain text lines with no ANSI escapes and no carriage-return redraws. `MISE_QUIET=1` silences it entirely.
- bb sends service output to `~/.bb/logs/*` and never to the terminal. The entrypoint runs bb behind a small init that tails both log files, so `make run` and `podman logs bb` both show them.
- `make run` and `make hack` share the same volume, so a CLI you install or log into in the shell is visible to the server.
- The toolset has to be the *global* mise config, which is what `MISE_GLOBAL_CONFIG_FILE` points at. Moving it to the system config at `/etc/mise` looks tidier and reads identically, but mise only creates bootstrap shims for tools from the user and project scope, so every lazy tool would silently lose its shim and first-use installation would stop working.
- `/opt/mise` is the install target for project pins, not just the baked toolset, and it has to stay writable at runtime. A shim resolves a repo's `mise.toml` when it runs, so this is the path that works for noninteractive callers such as git hooks, and no shell hook can relocate it for them: a `cd` hook never runs for noninteractive bash, `sh`, or a direct `execve`, and a wrapper in front of the shim breaks dispatch because mise reads the tool name from `argv[0]`. If a sandbox denies `/opt/mise`, first-use installs break; allow the writes, or bind a project directory over `/opt/mise/installs`. Versions live side by side under `installs/<tool>/<version>`, so sharing the directory across projects and threads is safe.
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
- Chromium writes fontconfig cache bookkeeping before it renders anything, and a write policy sees both attempts: a `chmod("/var/cache/fontconfig")` on every launch, because Debian lists that root-owned directory first and fontconfig chmods a cache directory it cannot write to, and an unlink of the `.uuid` marker beside each font directory when a cache has to be rebuilt. `FONTCONFIG_FILE` points fontconfig and Chromium at `/usr/local/share/bb/fonts.conf`, which is Debian's file with the system cache directories removed, so caches land in `~/.cache/fontconfig` and the chmod never happens. Two consequences for a sandboxed agent: allow writes under the xdg cache, and expect one round of `.uuid` prompts on a cold cache, since that path does not depend on the cache directory list. If you pass Playwright's `launch({ env })`, that object replaces the environment wholesale, so carry `FONTCONFIG_FILE` across or Chromium falls back to the distro file.
- `minimum_release_age` is unset, which is what lets the unpinned agent CLIs resolve to the newest release. Enabling it would hold them back; Omarchy zeroes it per invocation (`MISE_MINIMUM_RELEASE_AGE=0`) for the same reason.
- `node` is pinned by `NODE_VERSION` in the `Containerfile` as well as in `mise.toml`. That duplication is what keeps a toolset edit from rebuilding the node and bb layers, and the build fails if the two disagree.
- Bumping the node version means reinstalling bb, since bb lives inside mise's node install.
