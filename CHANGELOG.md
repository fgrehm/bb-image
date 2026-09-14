# Changelog

Two versions move independently. **bb** owns the bare semver tags (`0.43.1`, `0.43`) and is baked into the image from `BB_VERSION` in the `Containerfile`. **The image** owns the `v*` git tags, published as `img-<tag>` alongside `latest`. An entry here belongs to the image version and names the bb version it carries.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the image follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) with the bump meanings recorded in `AGENTS.md`: major for how the image is run, minor for new tools or a version bump, patch for a bb bump or a fix that moves nothing else.

## [Unreleased]

### Changed

- Chromium keeps its fontconfig caches in `~/.cache/fontconfig` and nowhere else. A sandboxed agent running Playwright used to be denied a `chmod("/var/cache/fontconfig")` that fontconfig attempts on every browser launch, because Debian lists that root-owned directory first. The image now sets `FONTCONFIG_FILE` to `/usr/local/share/bb/fonts.conf`, which is Debian's file with the system cache directories removed, so that write is never attempted and the cache lands in the home volume. Rendering is unchanged; the build fails if the shipped file drifts from the distro's.

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
