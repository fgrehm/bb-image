# bb-image

Container image for running [bb](https://getbb.app). `README.md` is the user-facing entry point, with detailed guides under `docs/`; this file is the working context for agents.

## Layout

- `container/` — the image and what it contains:
  - `container/Containerfile` — the recipe, one multi-stage file for the family: a pinned Debian 13, an internal `foundation` stage (distro, the unprivileged user, mise with its data outside home, and the packages in `container/packages-foundation.txt`), then named variant stages branching off it (`full`, `slim`, both container sudo variants, the systemd-based `vm` and `vm-sudo`, and the exe.dev adapter `exedev`), with a final empty `release` stage so a bare build and an explicit target cannot diverge. No verification RUNs anywhere: the Containerfile only builds.
  - `container/packages-*.txt` — the per-stage package inventories, one package per line with the rationale comments. Version ARGs live once before the first `FROM`; stages redeclare bare. The Makefile and check fragments read those ARGs with sed, so a value pin must stay on a single line each.
  - `container/entrypoint.sh` — PID 1 for container flavors. Runs bb behind a log tail and forwards signals; VM flavors boot systemd and use `bb.service` instead.
  - `container/fonts.conf` — the fontconfig override the image points `FONTCONFIG_FILE` at. Debian's file with the system cache directories removed, so the `chmod("/var/cache/fontconfig")` fontconfig attempts on every browser launch never happens. `container/fontconfig.sh` compares it against the distro file under `make check`.
  - `container/fontconfig.sh` — the drift guard and the regeneration for `fonts.conf`, kept next to the file they guard. `check` mode diffs the shipped file against the distro's (comments stripped) and asserts the single xdg cachedir and the absolute conf.d include; `regen` mode rewrites it.
  - `container/fonts-cache.inc` — the cache block `fontconfig.sh regen` splices in, kept as its own file so the regen path and the shipped file share the same text.
- `docs/` — user guides for running, tooling and hydration, backups, derived images, bb development, smolvm, and publishing.
- `mise.toml` — the image's toolset, installed as the global mise config at `/opt/mise/config.toml`. It stays at the repo root because it is also the project config mise's shims resolve for work in this repo; moving it under `container/` would change that.
- `build/` — host-side verification tooling: `build/check.sh` is the `make check` runner; it sources `build/check/lib.sh` for the shared helpers and runs every fragment in `build/check/` whose `# check-flavors:` declaration contains the requested FLAVOR, in lexical order (one file per concern, each independently shellchecked). A fragment that declares no flavor, or a flavor the harness does not know, fails the run, so nothing starts checking a new variant by accident. Every variant stage stamps an `sh.bb.flavor` OCI label and the runner refuses an image marked as another flavor. `build/fcshim.c` is the LD_PRELOAD interposer that turns the fontconfig "no writes on the system cache" claim into a release gate: make check compiles it fresh, proves its path-resolving wrappers are active, drives two Chromium launches with it, and refuses the release on any observed fontconfig-related write outside the accepted xdg-cache and cold `.uuid` classes, or on a warm-cache launch that writes anything at all.
- `.containerignore` and `.dockerignore` — build-context exclusions for podman and docker respectively: two real files (docker does not promise to follow a symlinked ignore file), kept in step by an exact-header assertion in `make check`.
- `examples/smolvm/Smolfile` — the original worked definition for running a container flavor as a [smolvm](https://smolmachines.com) microVM; `examples/smolvm-systemd/Smolfile` is the supported smolvm systemd VM-flavor definition; `docs/exedev.md` covers the separate exe.dev adapter.
- `Makefile` — `build`, `ci` (build + check in one), `check`, the host-only `check-smolvm-systemd`, `fonts-regen`, `hack`, `run`, `release`; FLAVOR selects the variant (`make ci FLAVOR=slim TAG=slim`), the security options and the Containerfile target follow from it, and unsuffixed invocations mean full as always.
- `.pre-commit-config.yaml` — shellcheck and shfmt as a pre-commit/prek hook, so a push that `make check` would refuse does not reach the tree in the first place. The in-image lint pass is the authority; these hooks are the cheap local pass.
- `.github/workflows/publish.yml` — builds every published variant (`full`, `slim`, `slim-sudo`, `full-sudo`, `vm`, `vm-sudo`, `exedev`) through a matrix to its own staging tag and runs the flavor-matching `make check` before pushing to GHCR; the `vm`, `vm-sudo`, and `exedev` jobs additionally run the cached, pinned smolvm host gate against the staged image; the exedev gate checks its systemd, SSH, host-key, and port-3000 contract, while live exe.dev creation remains a manual integration check; the release job runs only after every variant verified. On a tag it emits both axes: the bb version from `container/Containerfile` and `img-<tag>` for the image itself, with `-<variant>` suffixes for the non-full flavors. A `main` push that only touches markdown, `examples/`, `LICENSE` or `.gitignore` skips the build; path filters are not evaluated for tag pushes, so a release always builds.
- `make check` is the verification harness and the only place assertions live: the Containerfile carries none. It runs build/check.sh against the built image, which includes container/fontconfig.sh for the fonts.conf drift guard. CI runs it before the push step, so a release cannot ship while any check fails. Forwarded token works the same way it does for build.
- `make ci` is build + check as one target, the same two steps the publish workflow runs separately (its split exists only because buildx's GHA cache and the image attestations live in the build step; the check already runs against the self-same staged builder instance). Locally, use `make ci` and there is no ordering to get wrong.
- `make fonts-regen` rewrites container/fonts.conf from the distro fontconfig inside the image, and validates the result with the drift guard before replacing the file.
- `make hack` opens a shell in the image, with the same volume as `run`.
- `make run` serves bb with persistent state.

Verification is `make check`; for anything not covered by it, build the image and exercise it.

## Design decisions worth not undoing

- **Everything the image owns stays out of `$HOME`, with two exceptions.** Container home is volume-backed and seeded from the image once; VM home lives on the persistent machine disk. In both cases, image-owned files under home can freeze at first boot and shadow later image updates. That is why the toolset, mise's data dir, and the Playwright browsers are under `/opt`. The two exceptions: caches are not declarative, so nothing about them can be pinned in the image, which puts runtime caches in persistent home state; and the hydration-managed files (`~/.bb/AGENTS.md`, the rc blocks) are there because they have to be, but startup reconciliation (the container entrypoint or VM `bb.service`) keeps unmodified copies current. The registry they hydrate from lives at `/usr/local/share/bb`, outside persistent home state, because the frozen home copy cannot vouch for itself. Build-time caches still go to `/tmp` inside the `RUN` that creates them, because a delete in a later layer reclaims nothing.
- **The toolset is the *global* mise config, aimed there by `MISE_GLOBAL_CONFIG_FILE`, not the system config at `/etc/mise`.** The same file under `/etc/mise` reads perfectly well and looks tidier, but mise only creates bootstrap shims for tools it picks up from the user and project scope. Under `/etc/mise`, node and bb get shims, every lazy tool silently gets none, and first-use installation stops working with no error anywhere. This cost an afternoon once.
- **Only cheap tools are left to first use.** The toolchain is in the immutable image rather than container home, so a runtime-installed tool is gone when a container is recreated; VM disk state persists such installs until the machine is replaced. Expensive things (node, bb, Playwright's browsers) are baked instead.
- **The dev tools are baked too, even though they would be cheap to leave lazy.** ripgrep, jq, fd, shfmt, shellcheck, tmux, git-lfs and neovim are installed at build time because they are small and used constantly, and because the toolchain is not volume-backed, so a lazy copy would be re-fetched in every fresh container. The cost is that they live at and below `COPY mise.toml`, so a toolset edit re-downloads them. node, bb and Chromium sit above that `COPY` and stay cached. Baking is why the layer below the `COPY` is no longer free to rebuild.
- **The verification harness needs the baked lint and audit tools, and that is by design:** `make check` runs shfmt, shellcheck and gitleaks over the repo's scripts, tree and git history inside the image itself, so the scripts are linted and leak-scanned by the same versions that ship with the image. A lazy shfmt or gitleaks would make the check depend on first-use install state.
- **neovim is aliased to `vi` and `vim` for the whole container**, via wrapper scripts in `/usr/local/bin` rather than a symlink (see the rules below). `EDITOR` and `VISUAL` point at `vi`.
- **Fontconfig is aimed at a copy of Debian's file that has no system cache directory.** `FcDirCacheWrite` walks the cachedirs in order and, when a directory exists but the write probe fails, calls `chmod(dir, 0755)`. Debian lists `/var/cache/fontconfig` first, which is root-owned image content, so every sandboxed Chromium launch is denied that chmod. fontconfig can add cache directories but never prune one (`<reset-dirs/>` covers `<dir>` only), so the distro file cannot be trimmed by including it: `fonts.conf` is a replacement, and it names the xdg cachedir explicitly because a config with no `<cachedir>` at all makes fontconfig re-add the system one from its compiled-in defaults. `FONTCONFIG_FILE` rather than a patch to `/etc/fonts/fonts.conf`, so a derived image can point somewhere else, and an `ENV` in the last block rather than up with the others, for the layer-cache reason above. Chromium bundles its own fontconfig and honours the variable, and Playwright passes `process.env` to the browser, so the value reaches it; a caller that passes `launch({ env })` replaces that environment and has to carry the variable itself.
- **Layer order has real consequences.** `COPY mise.toml` sits third from last on purpose. node, bb, and Playwright are installed above it, from `NODE_VERSION`, `BB_VERSION`, and `PLAYWRIGHT_VERSION`, so only the layers at or below the `COPY` depend on the toolset, and those are the only ones a toolset edit rebuilds. Moving the `COPY` earlier makes every toolset edit re-download everything.
- **`NODE_VERSION` is duplicated on purpose.** It appears both here and in `mise.toml`, because a layer cannot both install node and depend on the file that declares it. `make check` asserts the two agree; bumping it in only one place fails the check rather than shipping a mismatch.
- **Agent CLIs and prek stay unpinned** (`version = "latest"`) so a fresh container resolves the current release. node, bb, and Playwright are pinned because they are baked.
- **`make run` and `make hack` pass `--security-opt no-new-privileges` for standard container flavors.** The base packages bring the standard Debian setuid binaries, including `su` and `mount`, and none of it serves this image's purpose, so agents should not be able to parlay it into container root. Bubblewrap is unaffected, since creating a user namespace is not a privilege gain. Choosing a `-sudo` container flavor drops the flag because passwordless sudo depends on setuid. VM flavors also omit it because systemd needs the VM-grade workload profile, even though standard `vm` contains no sudo. Override with `SECURITY_OPTS=` when `su` is genuinely needed. Changing container run flags this way is a major bump under the table below.
- **`WORKDIR` is `$HOME`, not a single mount point**, because bb hosts many projects and resolves them by path.
- **Containers use one volume, the whole home directory** (`bb-home`). Provider logins, git config, ssh keys, shell history, and bb state all persist with no per-CLI mount list. It is seeded from the image on first creation, and it stays small only because nothing heavy is in `$HOME`. VM flavors use the persistent machine disk instead.
- **`--userns=keep-id` is required for bind mounts under rootless podman.** Without it, container uid 1000 maps to a subuid and writes to a mounted project fail with permission denied.
- **The container entrypoint exists for signals.** bb sends service output to files and never to stdout, so the obvious container implementation is `exec tail -F` as PID 1, which means `podman stop` SIGKILLs bb. Instead the entrypoint backgrounds bb, tails the logs, and forwards SIGTERM so bb shuts down cleanly and exits 0. It deliberately does no mise reshimming: the shim farm is in the image at `/opt/mise/shims`, never shadowed by a volume, so it does not need reconciliation. Its only reconcile step hydrates the managed home files through `container/hydrate-home.sh`: a named volume is seeded once, so without it an existing volume never picks up later image updates to `~/.bb/AGENTS.md` or the rc blocks. Hash comparison against the registry makes user edits win; `managed-prev.tsv` records hashes a content change replaces, and a managed source edit **must** append its old hash to that file in the same commit, or shipped volumes silently keep the old version forever. Concurrent starts of the same image are safe by construction: temp files have unique names, the rename is atomic, and both writers produce identical content, so the last rename wins.

## Rules that are easy to break

- npm gates native-addon install scripts. bb is broken without `--allow-scripts=@parcel/watcher,better-sqlite3,node-pty`; it installs cleanly and fails at runtime otherwise.
- In the entrypoint, a trapped signal makes `wait` return early with a status above 128, before the child has exited. The wait loop exists so bb's real exit code reaches the container. Removing it makes `podman stop` report 143 instead of 0.
- Editing `mise.toml` should rebuild only the last three layers. If a toolset edit re-downloads node, reinstalls bb, or re-fetches Chromium, the `COPY mise.toml` has drifted upward.
- A layer is a stack, and a delete in a later layer is only a whiteout: bytes written in one layer still count toward the image size after a later layer removes them. Verified with a throwaway 200MB layer, where the same delete in a separate `RUN` left the image at 277MB instead of 77MB. So every `RUN` that downloads exports `npm_config_cache`, `XDG_CACHE_HOME`, and `XDG_STATE_HOME` into `$BUILD_SCRATCH` and removes it before the `RUN` ends. `BUILD_SCRATCH` is an `ARG`, not an `ENV`, so none of it reaches the runtime image. Removing these exports, or moving the `rm` into a later `RUN`, silently puts the bytes back.
- Playwright's browsers need `PLAYWRIGHT_BROWSERS_PATH` to point at `/opt/ms-playwright`, and the directory has to be owned by the user, or the download lands in the home volume and gets copied on every fresh volume.
- `fonts.conf` is a copy of Debian's, so a font package bump that moves the distro file needs it regenerated in the same commit. `container/fontconfig.sh check` compares the two with comments, blank lines and indentation stripped, and `make check` fails on drift, so the failure mode is a refused release rather than silently dropped font directories or alias rules. It also asserts exactly one cachedir, the xdg one, and the absolute `conf.d` include, which the diff cannot see because those are the deliberate differences. Comments and formatting are free: only the content between them is compared. Regenerate with `make fonts-regen`.
- `/opt/mise` is owned by and writable by `developer`, and it has to stay that way: derived images add tools to it with `mise install` and `npm install -g`, and those have to keep working. Run those as `developer` (the container flavors' default user and the VM service user); a `mise install` as root writes root-owned directories that `developer` can no longer extend. There is no repair that survives the image pipeline: a POSIX default ACL on `/opt/mise` works in a live container but is dropped by `podman build`, `commit` and `export`, verified, so it never reaches a published image. `make check` asserts the writability as `developer`, so a broken layer fails the check before a release ships. See `docs/derived-images.md`.
- **The backup script is baked, and its timer is not.** `/usr/local/share/bb/bb-backup` (symlinked as `bb-backup`) has three subcommands and no default strategy: `backup` tars the persistent state to a zstd archive, snapshots live sqlite dbs with `sqlite3 .backup` when named via `--sqlite` so `~/.bb/bb.db` is not a mid-write page mix, verifies the archive with `zstd -t` plus a full `tar -tf` pass before renaming it into place, and prunes with `--keep N`; `traces` is the strictly additive rsync mirror of pi sessions, bb logs, the pi bridge, and claude/codex state, incremental against a nanosecond `.traces-last` marker, never pruned or deleted, with `--flatten` for the merge-into-target layout; `verify` re-runs the integrity check. No schedule is baked: a container deployment uses a host systemd user timer or compose sidecar cron, while a derived VM may add a guest timer once its destination and retention policy are known. `build/check/55_backup.sh` runs the round trips inside the image, including refusing a truncated archive and refusing a bare invocation.
- `/opt/mise` also has to stay writable wherever an agent runs sandboxed, and it is the install target for project pins, not only the baked toolset. A mise shim resolves the current repo's `mise.toml` when it is invoked, which is the only mechanism that reaches noninteractive callers such as git hooks. A shell hook cannot replace it: a `cd` hook never runs for noninteractive bash, `sh`, or a direct `execve`, and a wrapper in front of the shim breaks dispatch because mise reads the tool name from `argv[0]` (the same trap as the `vi`/`vim` wrappers above). If a sandbox denies `/opt/mise`, first-use installs of project pins fail there; allow the writes, or bind a project directory over `/opt/mise/installs`. Installs are versioned under `installs/<tool>/<version>`, so sharing `/opt/mise` across projects and threads is safe. This is why project-scoped `MISE_DATA_DIR` is deliberately not implemented: documenting the invariant is the whole fix.
- `BB_VERSION` in the `Containerfile` pins bb, and the publish workflow reads it from there to keep the tag and the baked version in step. The image's own version comes from the git tag, so bb tags and image tags stay on separate axes.
- bb routes service output to `~/.bb/logs/*`. Container entrypoint replacements must preserve visibility deliberately; VM users inspect those files while systemd reports unit state.
- mise's shims are symlinks to the `mise` binary and it dispatches on the tool name in `argv[0]`. So `vi` and `vim` are wrapper scripts in `/usr/local/bin` that `exec nvim "$@"`, not symlinks to `/opt/mise/shims/nvim`. A symlink reached as `vim` fails with "vim is not a valid shim". Nothing shadows the wrappers because mise's neovim declares `bins = ["nvim"]`; if a `vi` or `vim` shim ever appears, make check's shim scan refuses before a release ships.
- mise writes into `$HOME` if nothing redirects it: `~/.cache/sigstore-rust` from verifying the aqua-backed tools, and `~/.local/state/mise`. Neither `MISE_CACHE_DIR` nor a pinned state directory covers the sigstore one, which follows `XDG_CACHE_HOME`. `$BUILD_SCRATCH` handles both during the build, and the toolset `RUN` still ends with an `rm -rf` of `~/.cache` and `~/.local` as a guard. That `rm` stays last in the `RUN`, because `node --version` and `bb --version` go through shims and run mise again.
- The build token is forwarded as a BuildKit secret, and the mount needs `uid=1000,gid=1000,mode=0400`. The toolset RUNs run as the unprivileged `developer`, and a secret mounted with default permissions is unreadable to it. `cat` then fails inside a command substitution, which does not trip `set -e`, so the build carries on with an empty token and mise stays unauthenticated while looking exactly like the rate limiting the token was meant to fix. Keep that uid in step with `USER_UID`.
- The token must never be a build arg or an `ENV`, both of which persist in image metadata, and must never be echoed: podman does not redact secrets from build output the way BuildKit does. make check greps essentially the whole of the built image filesystem for it (the scan runs as root inside the image, so /root is inside the scan; the token reaches grep through stdin, never disk or an argument; unreadable paths and whiteouted bytes are the documented blind spots) and refuses the release if it is anywhere on disk.
- That filesystem guard cannot see bytes in a lower layer that a later layer deleted, since the content is whiteouted rather than removed. Verified: a leak written in one RUN and deleted in the next is invisible to the guard and still present in the saved image. The sentinel scan below is the only check that catches it.
- bubblewrap is installed for agent sandboxing and is deliberately not setuid. It works under podman's default seccomp, because unprivileged user namespaces are permitted there, but a fresh `--proc` mount combined with PID-namespace unsharing fails inside the container with `Can't mount proc on /proc: Operation not permitted`. Only `--privileged` lifts that. `--security-opt seccomp=unconfined`, `apparmor=unconfined`, `label=disable` and `--cap-add SYS_ADMIN` all fail to, and bwrap will not start with extra capabilities anyway (`Unexpected capabilities but not setuid`). Do not add `--privileged` to `make run` without deciding to give up the container's isolation. This is specific to containers: the same command works in a smolvm microVM, where there is no nesting, so do not carry the workaround over there.
- Publishing bb's port on every interface breaks `localhost` on this podman and pasta (6.1.1 with 2026_07_28.f8df3f1). A wildcard publish makes pasta listen dual-stack, IPv6 connections are reset while IPv4 works, and `localhost` resolves to `::1` first, so clients fail against a port that is genuinely open. That is why `make run` publishes `127.0.0.1`, via `BB_BIND`; it also keeps bb off the LAN, which suits a local single-user tool. Set `BB_BIND=0.0.0.0` on purpose and reach it by IPv4 address. `--network=host` is the fallback for other rootless networking problems.
- Debian's `/etc/profile` resets `PATH`, which drops the mise shims, so `bash -l` and anything bb spawns through a login shell loses every lazy tool. `/etc/profile.d/mise-shims.sh` puts them back. zsh does not need it: `/etc/zsh/zshenv` only sets `PATH` when it is empty, so the image's `ENV PATH` survives, and `~/.zshrc` carries `mise activate zsh` for interactive use. zsh is not the default shell for `developer`; `useradd` sets bash.

## Variants

The Containerfile is one multi-stage recipe for the family: internal `foundation` (Debian, the user, mise, `container/packages-foundation.txt`), then `slim` (node, bb, `mise-slim.toml`'s lazy pnpm and agent CLIs, `agents-slim.md` guidance), `slim-sudo`, `full` (the batteries, `container/packages-full.txt`), `full-sudo`, `vm` (full plus systemd and `bb.service`), `vm-sudo` (vm plus passwordless guest sudo), and `exedev` (vm plus SSH and exe.dev integration), with an empty final `release` stage so a bare build and an explicit target cannot diverge; new stages must not follow it. Variant identity is the `sh.bb.flavor` label, stamped per stage, and `make check FLAVOR=...` refuses a mismatch, so an image can only be verified as what it is.

Tag policy follows the variant: full keeps every unsuffixed tag (`latest`, `edge`, bb-version tags, `img-<version>`); other flavors get suffixed pins (`0.44.0-slim`, `img-<version>-full-sudo`, `edge-vm`, `edge-vm-sudo`, `edge-exedev`) plus a bare moving `slim` alias that mirrors `latest` for the slim image specifically. Sudo flavors drop `--security-opt no-new-privileges` (make derives that flag from the FLAVOR); there is no middle ground where sudo is installed but unusable. The VM flavors are not container run profiles: `vm` and `vm-sudo` use systemd as PID 1 and require smolvm's default VM-grade workload; `exedev` uses systemd plus SSH and exe.dev's init/login conventions. `vm` follows full's no-sudo posture and `vm-sudo` explicitly adds passwordless guest sudo. There is no `bb:source` variant: full-sudo proved bb-from-source (install, native compile, dev boot) with no missing OS packages, so a dedicated image would only duplicate prerequisites. Worker enrollment remains separate future work; `vm` provides the init and persistence foundation but does not enroll itself.

Contracts that derived images rely on, and are upstream invariants not to break casually: the `sh.bb.flavor` label is identity and survives derivation; the baked container command is optional for a derived container image that replaces startup (hydration and log mirroring then skip), while VM derivations use `bb.service`; and the hydration registry carries no username-dependent paths (`usermod` rename machinery in downstream images keeps working across digests). All three came out of pAIr00t's live repin onto a new base digest; they are documented in `docs/derived-images.md`.

Careful with a sudo image at the operator level: sudo is confined to the rootless container or microVM guest, but either becomes a different threat model when given host SSH credentials, broad host mounts, or a container-engine socket.

## Releasing

Two version axes. The bb release comes from `BB_VERSION` in the Containerfile; the image's own version comes from the git tag, and the workflow reads both so a published tag cannot disagree with what is baked inside.

| Bump | Meaning |
| --- | --- |
| major | changes how the image is run: working directory, volume layout, ports, security options |
| minor | new tools, a node or mise bump, a base digest refresh |
| patch | a bb version bump, or a fix that moves nothing else |

`make release VERSION=0.2.0` tags and pushes, which triggers the workflow. The tag is signed and its message records the bb version so `git tag -n1` answers which bb is in which image without opening the Containerfile.

A prerelease suffix such as `0.3.0-rc1` publishes `img-0.3.0-rc1` and nothing else. The bb aliases and `latest` are gated on stable tags, because otherwise an rc would silently become what people pull.

## Keeping the changelog

`CHANGELOG.md` is the user-facing record of what changed. It exists so someone can decide whether to pull a new tag without reading `git log`, which means the test for an entry is "would a user of this image notice?"

Write an entry when a change:

- adds or removes a tool, package, or baked file
- moves a version: bb, node, mise, Playwright, or the base digest
- changes how the image is run, meaning flags, ports, volumes, working directory, or the security posture
- changes the image size in either direction
- fixes something a user could have hit, including a broken port, a missing shim, or a confusing failure

Do not log internal churn. Refactors, comment edits, doc rewrites, and workflow tidy-ups get no entry unless they change what a user gets. The cache rework earned an entry because it moved 170MB and changed where caches live; renaming a variable would not.

Practical rules:

- Put entries under `## [Unreleased]`, newest release first, using the Keep a Changelog headings: Added, Changed, Deprecated, Removed, Fixed, Security. `Known limitations` is used here too, since a first release has more of those than most projects.
- `make release` does not write the changelog. When releasing, rename `## [Unreleased]` to `## [<version>] - <YYYY-MM-DD>` and start a fresh empty `Unreleased` above it, in the same commit as the tag.
- Name the bb version whenever `BB_VERSION` moves. The changelog tracks the image's own version; bb rides its own axis, and an entry that says "carries bb 0.44.0" answers the question people actually have.
- Describe the effect on the user, not the implementation. "Reading PDFs now works through poppler" beats "added poppler-utils to the apt list".

## Verifying a change

```bash
make build
make check
```

`make check` is the whole assertion set: node/bb/playwright versions in the built image, the shim layout and the vi/vim alias, shfmt and shellcheck over every script in the repo, a gitleaks scan of the repo tree and its full git history, the `fonts.conf` drift guard with cachedir and `fc-match` parity, a login-shell smoke, the two-launch Chromium test, one lazy first-use install (`go version`), the writable mise dir, the hydration behaviour test (fresh install, user edit preserved, stale copy replaced), the token leak scan, and the home-size bound. CI runs the same thing before the push step, so a release cannot ship while any check fails.

When a check fails, these run the pieces by hand:

```bash
podman run --rm bb:dev /bin/bash -c 'node --version; bb --version; playwright --version; pwd'
podman run --rm bb:dev /bin/bash -c 'ls /opt/mise/shims | grep -E "^(go|prek|claude)$"'
```

First-use installs are the most likely thing to regress. Exercise one directly:

```bash
podman run --rm bb:dev /bin/bash -c 'go version'
```

Chromium needs its system libraries, so check that it launches rather than trusting that the download succeeded:

```bash
podman run --rm bb:dev /bin/bash -c 'cd "$(npm root -g)" && node -e "require(\"playwright\").chromium.launch().then(async b => { console.log(\"ok\"); await b.close(); })"'
```

Regenerating `fonts.conf` is `make fonts-regen`, not hand editing: it runs
container/fontconfig.sh's sed recipe (description, an absolute `conf.d` include, the cache directory list)
against the distro file inside the image, keeps the shipped header comment and the
shipped cache block, and refuses to replace the file if the result would not pass
the drift guard.

Home should stay near 24K; `make check` trips at 48K. If home grows, something is writing build residue into `$HOME` that the home volume will copy on first boot. The usual culprits are mise's `~/.cache/sigstore-rust` and `~/.local/state/mise`, which appear whenever anything runs a shim without `$BUILD_SCRATCH` set:

```bash
podman run --rm bb:dev du -sh /home/developer
```

No build-time cache should survive into the image, while runtime caches should land in home:

```bash
podman run --rm bb:dev /bin/bash -c 'ls -d /opt/npm-cache /opt/mise/cache 2>/dev/null || echo "no build caches, correct"'
podman run --rm bb:dev /bin/bash -c 'gh --version >/dev/null 2>&1; find /home/developer/.cache -mindepth 1 -maxdepth 1'
```

The token check. There are two halves, and the checks only cover one of them, so
build with a sentinel and scan the saved archive, which sees whiteouted bytes as well:
```bash
SENT='ghp_sentinel_donotleak_0123456789abcdef'
make build GH_TOKEN="$SENT"
podman save bb:dev -o /tmp/img.tar && mkdir -p /tmp/img.x && tar -xf /tmp/img.tar -C /tmp/img.x
grep -rlF "$SENT" /tmp/img.x | head    # expect no output
rm -rf /tmp/img.tar /tmp/img.x
```

make check's token half should print `no matches`, or `skipped, no GH_TOKEN supplied`
when there is no token. Both are a pass.

bubblewrap is present for agent sandboxing. Check the binary and a working sandbox, since a
missing or setuid `bwrap` both matter:

```bash
podman run --rm bb:dev /bin/bash -c 'bwrap --version; ls -l "$(command -v bwrap)"'
podman run --rm bb:dev /bin/bash -c 'bwrap --ro-bind / / --dev /dev --unshare-all -- echo sandboxed'
```

Do not expect a fresh `--proc` mount with PID-namespace unsharing to work; that is the
container limitation documented above, not a packaging problem.

Check that shutdown is still clean. Wait for bb to finish starting first. The entrypoint
forwards SIGTERM to bb, and a bb that has not installed its handler yet dies to the
default action, so a stop issued during startup reports 143 on any revision, including
revisions that were never touched:

```bash
podman run -d --name bbtest -p 127.0.0.1:39999:38886 --userns=keep-id bb:dev
until podman logs bbtest 2>&1 | grep -q "Host daemon started"; do sleep 1; done
podman stop -t 20 bbtest   # then confirm exit code 0, not 143 or 137
```

## Testing etiquette

Name test containers (`--name bbtest`) and remove them explicitly. A container left running holds its published port, which makes the next run fail to bind while something else answers on that port, and `podman ps --filter name=bb` is a substring match that will happily show you an unrelated `bb-yard-*` container. Use exact names or inspect the container by ID when checking status. Also check the port is free before concluding a run failed for another reason.

## Review discipline

Adversarial or code-review prompts and their findings are artifacts, not chat content: prompts live in `.agents/scratchpad/adversarial-review.md`, and findings written by reviewing agents go into a sibling `adversarial-review-*findings*.md` next to the prompt or round they belong to. Reviewing agents run nothing, please: no builds, containers, or commits; read the diff and the tree and report findings to the file.
