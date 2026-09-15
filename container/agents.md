# Toolchains in this container

Tools are managed by mise. The data dir is `/opt/mise` and its shims are on PATH. A repo's own AGENTS.md overrides this file.

- Run a tool by name. A lazy tool installs itself on first use.
- A repo declaring tools (`mise.toml`, `.mise.toml`, `.tool-versions`) is resolved automatically, including from git hooks and scripts. Do not export anything to make it work.
- Add a project dependency with `mise use <tool>@<version>` at the repo root, then commit the `mise.toml`.
- Plain versions need no trust. `[settings]`, `[env]`, inline tables, or templated tasks need `mise trust` first.
- Keep `/opt/mise` developer-owned and writable. Never install as root or chown it, or every later install breaks.
- bb runs from mise's node. Do not change the node version or reinstall it.
- After `npm install -g` of a tool with binaries, run `mise reshim`.
- Playwright and its Chromium are baked: the package is an npm global (not mise-managed) and the browsers live at `/opt/ms-playwright`. Use them as-is; do not run `playwright install` or reinstall the package.
- If you pass Playwright's `launch({ env })`, the object replaces the inherited environment wholesale, so carry `FONTCONFIG_FILE` across or Chromium loses the container's fontconfig setup.
- Sandboxes must leave `/opt/mise` writable. There is no `MISE_DATA_DIR` hook to relocate it.
