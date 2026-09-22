# Changelog

Two versions move independently. **bb** owns the bare semver tags (`0.43.1`, `0.43`) and is baked into the image from `BB_VERSION` in the `Containerfile`. **The image** owns the `v*` git tags, published as `img-<tag>` alongside `latest`. An entry here belongs to the image version and names the bb version it carries.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the image follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) with the bump meanings recorded in `AGENTS.md`: major for how the image is run, minor for new tools or a version bump, patch for a bb bump or a fix that moves nothing else.

## [Unreleased]

## [0.3.0] - 2026-09-22

Carries bb 0.43.3.

### Added

- `gitleaks` 8.30.1 is baked into the full image's toolset and runs as part of every `make check` and CI pass: the scan covers the repo's working tree and full git history, so a release cannot ship with a secret in the repo, and the `pre-commit`/prek hooks gained a staged-changes gitleaks pass so nothing lands unscanned locally. (The existing token scan on the built image's filesystem is unchanged and separate.)
- Image variants, built from one shared `foundation` stage of the same Containerfile. `full` is what `bb`, `latest` and every unsuffixed tag has always meant, unchanged. New: `slim` (node, bb, mise, lazy pnpm and the agent CLIs; no Chromium, dev tools, DB clients, document tools, compilers or sudo; about 925MB against full's around 2,400MB), `slim-sudo` and `full-sudo` (the matching flavor plus passwordless sudo). Published tags carry the variant suffix (`0.43.1-slim`, `img-<version>-full-sudo`, `edge-slim`); the unsuffixed aliases stay on full, and `latest` and `slim` are the two moving aliases. Foundation itself is internal and is not published. The in-container `~/.bb/AGENTS.md` guidance is one flavor-neutral text shared by every variant, so a home volume moved from full to slim, or back, hydrates like any other image update instead of preserving the other flavor's wording.
- Checks are flavor-aware, and every variant must pass its own verification before a release ships: the build now boots bb behind the entrypoint in every flavor and asserts a clean stop, and slim refuses the full image's packages by inspection plus a size ceiling, so a slim build can never pass verification because it was run as full (identity is stamped as the `sh.bb.flavor` OCI label and the harness refuses a mismatch).

### Changed

- Bumps the baked bb release from 0.43.1 to 0.43.3 across all image variants.

- Tool package-manager and compiler cache paths are now declared instead of left to each tool's default. They ship twice: as plain image ENVs (`npm_config_cache` now under `~/.cache/npm`, where npm used to own `~/.npm`; the pnpm store-dir under both `pnpm_config_*` and `npm_config_*` prefixes so repo-pinned pnpm 9.x and 12.x resolve identically; `CARGO_HOME`, `GOPATH`/`GOMODCACHE`/`GOCACHE`, `UV_CACHE_DIR`, and `TMPDIR=/tmp`), and as the same keys in the global mise config as `${HOME}`-relative entries resolved per container. The ENVs make the paths hold for every exec and shell; the mise entries make them correct for derived images that rename the user, which need to redeclare the ENVs only if the paths must be right outside mise contexts too. The motivation is sandbox-friendliness: checkable paths instead of per-tool probe noise (pnpm#9246's ancestor probing). For layouts that mount an existing home: existing caches remain where they are, and the declared paths simply start being used going forward.

- The full image grew about 2MB (under 0.1%): packages moved into a second layer when the `foundation` stage was extracted, which doubles the dpkg metadata written at build time. Nothing else in the full image changed: same packages, users, environment, and command as 0.2.0.

### Security

- Passwordless sudo is opt-in and confined to the rootless container. The sudo flavors must be launched without `no-new-privileges` (the make targets derive that flag from the chosen flavor automatically); the standard full and slim profiles keep it.

### Known limitations

- linux/amd64 and rootless Podman remain the tested scope.
- Runtime apt packages and mise tools live with the container: a `--rm` run loses them when it stops, so the sudo flavors and any interactively extended environment want a named home volume and a long-lived container.

## [0.2.0] - 2026-09-15

Carries bb 0.43.1.

### Added

- Home hydration. The container-level `~/.bb/AGENTS.md` (new in this release, see below) and the `mise activate` blocks in `~/.bashrc` and `~/.zshrc` live in the home volume, which is seeded from the image exactly once, so until now an existing volume never picked up later image updates. The entrypoint now reconciles them on every container start (`hydrate-home.sh`): a copy whose hash matches a version the image has shipped is replaced when the image moves on, a copy the user edited is left untouched, and the image's home is hydrated at build time too so a fresh volume is correct even for callers that bypass the entrypoint. The registry of shipped hashes lives at `/usr/local/share/bb`, outside the volume. A user edit is a permanent opt-out for that file; deleting it lets the image reinstall it.
- A container-level `~/.bb/AGENTS.md` shipped in the image: bb appends it to the system prompt of every provider-backed thread, so agents get in-container guidance on the mise toolchain (lazy installs, project pins, the `/opt/mise` ownership rule, and that Playwright and its Chromium are baked and must not be reinstalled). Users can fine-tune their copy in the volume, and edits are kept by the hydration mechanism.
- `bb-backup`, baked at `/usr/local/share/bb/bb-backup`, and `zstd` in the image. Subcommands, no default: `backup` tars the persistent state to a zstd archive, snapshots live SQLite databases (`~/.bb/bb.db` and friends) with `sqlite3 .backup` when named via `--sqlite` so the archive holds a consistent copy, verifies the archive (`zstd -t` plus a full `tar -tf` pass) before it is named so a corrupt or truncated archive never lands under the canonical name, re-runs the same check via `verify` for restore flows, and prunes with `--keep N`. `traces` mirrors pi sessions, bb logs, the pi bridge, and claude/codex state into an output directory with rsync, additively: no pruning or removal, only files newer than the last run, nanosecond marker precision, and `--flatten` for the `rsync src/* dest/` layout encrypted remote syncs want. Scheduling is deliberately not in the image: a host systemd user timer or a compose sidecar cron calls it (see README, Backups).

### Changed

- The entrypoint now performs one state-mutating step before bb starts, the hydration above. Everything else is unchanged: it still only tails bb's logs and forwards SIGTERM, and a hydration problem is logged and skipped, never fatal.

### Fixed

- First-use installs of lazy tools survive slow GitHub minutes. mise's default remote-version fetch timed out after 3s and cached the version list for only an hour, so `mise install <tool>` could fail outright against a slow api.github.com and retry more often than needed. The toolset now caches remote version lists for 24 hours and allows 15s per fetch. Shim invocations keep mise's hard-coded single ~3s attempt by design, so the residual warning noise on an uncached shim call is unchanged.

## [0.1.1] - 2026-09-14

Carries bb 0.43.1.

### Changed

- Verification moved out of the Containerfile entirely. The image recipe now only builds; everything it used to assert at build time (fonts.conf drift against the distro file, the token leak scan, the writable mise dir) plus the behavioural checks (launch smoke, fontconfig parity, first-use installs, home size) run through `make check`, and the publish workflow refuses to push an image until every check passes. `make check` also lint-scripts the repo with the baked shfmt and shellcheck, so the repo's scripts are linted by the tools inside the image.
- `make check` is split into per-concern fragments under `build/check/`; one small file per assertion instead of a single 300-line script, with a shared helper module and a thin runner.
- Claims about what the released image does are now measured, not remembered: baked tool versions are compared against the Containerfile ARGs, a login-shell check exercises `/etc/profile`, the token-leak scan fails closed on scan errors, fc-cache reports exactly one xdg cache dir, and a release is refused if Chromium's fontconfig writes leave the xdg cache (see the shim under Fixed).
- Source layout: the image recipe and its content live in `container/` (Containerfile, entrypoint.sh, fonts.conf, fontconfig.sh), host-side build tooling in `build/`, `mise.toml` at the root, and the build context is pruned by real `.containerignore` and `.dockerignore` copies kept in step. The image content itself barely changed: the entrypoint moved with a reformat-only diff, and removing the tail RUNs also removed the `/tmp` sigstore/mise residue their smoke write left behind, which shrinks the image slightly.
- shellcheck and shfmt also run as a pre-commit/prek hook (`.pre-commit-config.yaml`), so a push the harness would refuse does not reach the tree in the first place.

### Fixed

- Chromium keeps its fontconfig caches in `~/.cache/fontconfig` and nowhere else. A sandboxed agent running Playwright used to be denied a `chmod("/var/cache/fontconfig")` that fontconfig attempts on every browser launch, because Debian lists that root-owned directory first. The image now sets `FONTCONFIG_FILE` to `/usr/local/share/bb/fonts.conf`, which is Debian's file with the system cache directories removed, so that write is never attempted and the cache lands in the home volume. Rendering is unchanged; the claim is release-gated by an interposing shim (`build/fcshim.c`) that runs in `make check` and refuses a release on any fontconfig write outside the xdg cache.

### Known limitations

- A Chromium launch against a cold fontconfig cache still unlinks the `.uuid` marker in each font directory, because that path is reached when a directory cache has to be rebuilt and does not depend on the cache directory list. A sandbox that denies the unlink prompts once per fresh cache; the next launch is clean, and the cache lives in the home volume, so an agent sees it once rather than on every launch.

## [0.1.0] - 2026-09-13

First release. Carries bb 0.43.1.

### Added

- Debian 13 slim, pinned by digest, running as an unprivileged `developer` user (uid/gid 1000) with `$HOME` as the working directory.
- node 24.21.0, bb 0.43.1, and Playwright 1.63.0 with Chromium and its system libraries, all installed at build time, so serving and driving a browser needs no first-run download.
- mise 2026.9.5, with the toolset installed as the global config at `/opt/mise/config.toml`.
- Dev tools baked at build time: neovim (aliased to `vi` and `vim`), ripgrep (as `rg`), jq, fd, shfmt, shellcheck, tmux, and git-lfs.
- Installed on first use: pnpm, ruby, bun, go, rust, python, gh, prek, and the agent CLIs claude, codex, pi, opencode, grok and oh-my-pi.
- CLI and asset tooling: `procps`, `less`, `unzip`, `pkg-config`, `gnupg`, `rsync`, `wget`, `file`, `bubblewrap` for agent sandboxing, `imagemagick` with `cwebp`/`dwebp`, `pngquant`, `optipng` and `jpegoptim`, plus `poppler-utils` (`pdftotext`, `pdftoppm`, `pdfinfo`) and `qpdf` for PDFs.
- A UTF-8 locale (`LANG=C.UTF-8`) and `EDITOR`/`VISUAL` pointing at `vi`, so commits without `-m` and interactive rebases work.
- `/etc/profile.d/mise-shims.sh`, so login shells keep the mise shims that Debian's `/etc/profile` otherwise drops.
- One home volume (`bb-home`) covering provider logins, git and ssh config, shell history, and bb state.
- `examples/smolvm/Smolfile`, a worked definition for running the image as a [smolvm](https://smolmachines.com) microVM, verified against smolvm 1.16.0.

### Changed

- Runtime caches now belong to the volume. Nothing pins a cache location, so caches written at runtime live in the home volume and survive a container recreate, while build-time caches stay inside the `RUN` that creates them and never reach a layer. The image went from 2.52 GB to 2.39 GB across this and the tooling additions.
- `make run` publishes bb on `127.0.0.1` (`BB_BIND`) instead of every interface, which also fixes `http://localhost:38886` on podman with pasta.
- CI skips the image build when a `main` push only touches documentation. Tag pushes always build.

### Security

- `make run` and `make hack` pass `--security-opt no-new-privileges`, so the setuid binaries the base packages bring (`su`, `mount`, `passwd` and the rest) cannot be used to elevate.
- The build can authenticate its GitHub API calls with a token, supplied as a BuildKit secret and mounted read-only for the `RUN`s that need it. It is never an `ENV` or a build arg, and the final `RUN` greps the filesystem for it and fails the build if it lands on disk.
- `bubblewrap` is installed deliberately unsetuid.

### Known limitations

- `linux/amd64` only. `linux/arm64` is untested.
- Reading PDF and PostScript means using poppler, because ImageMagick's read path needs the ghostscript delegate, which is not installed. Writing a simple PDF from ImageMagick works.
- Inside a container, `bwrap` cannot mount a fresh `/proc` while unsharing the PID namespace without `--privileged`. In a smolvm microVM it works.
- Agent CLIs and prek are deliberately unpinned, so a fresh container resolves the current release. That needs network and is subject to GitHub's unauthenticated rate limit unless a token is supplied.
