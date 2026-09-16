# Toolchains in this container

Tools are managed by mise. The data dir is `/opt/mise` and its shims are on PATH. A repo's own AGENTS.md overrides this file.

- Run a tool by name. A lazy tool installs itself on first use.
- A repo declaring tools (`mise.toml`, `.mise.toml`, `.tool-versions`) is resolved automatically, including from git hooks and scripts. Do not export anything to make it work.
- Add a project dependency with `mise use <tool>@<version>` at the repo root, then commit the `mise.toml`.
- Plain versions need no trust. `[settings]`, `[env]`, inline tables, or templated tasks need `mise trust` first.
- Keep `/opt/mise` developer-owned and writable. Never install as root or chown it, or every later install breaks.
- bb runs from mise's node. Do not change the node version or reinstall it.
- After `npm install -g` of a tool with binaries, run `mise reshim`.
- What is baked varies by image flavor. Dev tools (neovim, ripgrep, jq, fd, tmux, git-lfs, shellcheck), Playwright with Chromium at `/opt/ms-playwright`, database clients, document tools, and compilers are guaranteed in the full image and absent from slim; check with `command -v <tool>` before assuming a tool is there. Use baked tools as-is; do not reinstall what the image already carries, and do not run `playwright install` where it is baked.
- Where Playwright is baked, its Chromium is launched with the container's fontconfig setup via `FONTCONFIG_FILE`; if you pass `launch({ env })` yourself, that environment is replaced wholesale, so carry `FONTCONFIG_FILE` across or the browser loses it.
- Sandboxes must leave `/opt/mise` writable. There is no `MISE_DATA_DIR` hook to relocate it.
