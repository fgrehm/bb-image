# Using this image as a base

The image is meant to be layered on. `/opt/mise`, the mise data dir, is owned by and writable by `developer`, so a derived image can add tools with `mise install` or `npm install -g` and they behave like the baked ones.

Run those as `developer`, which is the image's default user. If a `Containerfile` needs `USER root` for `apt-get`, a `chmod` or a `chown`, switch back with `USER developer` before any install:

```dockerfile
FROM ghcr.io/fgrehm/bb:0.43.4

USER root
RUN apt-get update && apt-get install -y --no-install-recommends your-tool \
    && rm -rf /var/lib/apt/lists/*

USER developer
RUN mise install go && mise reshim --force
```

A `mise install` run as `root` writes root-owned directories under `/opt/mise`, and `developer` cannot add versions to them afterwards. There is no permission fix for that which survives the image build, so keep installs as `developer`. The build asserts the `/opt/mise` ownership invariant, so a regression on the base side fails before it ships. That invariant also has to hold at runtime: anything that sandboxes an agent, whether a derived image or an external layer, must leave `/opt/mise` writable, or first-use installs of project pins fail there. See [mise and project pins](tooling.md#gotchas) for why there is no shell-hook workaround.

To replace the baked toolset rather than extend it, point `MISE_GLOBAL_CONFIG_FILE` at your own file. That replaces the global config at `/opt/mise/config.toml`; the two are not merged. Pin versions there when the derived image has to work without the network:

```dockerfile
COPY --chown=developer:developer my-tools.toml /opt/my-tools.toml
ENV MISE_GLOBAL_CONFIG_FILE=/opt/my-tools.toml
USER developer
RUN mise install && mise reshim --force
```

`MISE_GLOBAL_CONFIG_FILE` replaces mise's global config; it does not add another layer to the built-in config, and `~/.config/mise/conf.d/` is not read as a supplement when this override is set. Use `mise use -g` to add tools to the image's config, or provide one complete replacement file.

If the derived image changes Node's global pin, bb can stop resolving entirely with `mise ERROR No version is set for shim: bb-app`. bb is installed into the image's baked mise-managed Node version, so keep that version aligned with `NODE_VERSION` unless you also reinstall bb into the replacement Node installation.

For derived builds that add several aqua-backed tools, forward a GitHub token as a BuildKit secret. The secret must be readable by `developer`, and it must not be an `ARG` or `ENV`:

```dockerfile
RUN --mount=type=secret,id=github_token,required=false,uid=1000,gid=1000,mode=0400 \
    if [ -s /run/secrets/github_token ]; then \
      export MISE_GITHUB_TOKEN="$(cat /run/secrets/github_token)"; \
    fi; \
    mise install && mise reshim --force
```

Build with `--secret id=github_token,type=env,env=GH_TOKEN` (or the equivalent secret syntax for your builder). A token is not required, but it avoids GitHub's unauthenticated release API limit during cold builds.

Pinning is what removes the network round trip: a pinned version that is already installed runs offline. `MISE_OFFLINE=1` goes further and blocks HTTP entirely, turning a missing tool into a hard failure at the point of use. `MISE_LOCKED=1` with a `mise lock` lockfile does the same for `mise install`. Neither silences the resolution warnings for any unpinned `latest` tools left in the config, so pin or drop those as well if the derived image has to be quiet and fully offline. If unpinned agent CLIs (`claude`, `codex`, ...) emit rate-limit warnings when a tokenless build resolves them, `MISE_GITHUB_TOKEN` in the environment is the quiet path; the base build keeps them unpinned on purpose so a fresh container resolves the current release. The baked config gives version fetches 15 seconds and caches the catalog for a day (`fetch_remote_versions_timeout`, `fetch_remote_versions_cache`) — but a shim invocation itself is capped by mise at ~3s no matter what, so a slow resolution falls back silently and warns; only a direct `mise install` inherits the wider window.

## Contracts a derived image can rely on

- **Identity marker.** Every variant stamps an `sh.bb.flavor` OCI label, and the check harness refuses to run an image's checks under another flavor's marker. Derived images keep the label inherited from the base stage they build from; re-stamp only when your derivation changes the contract enough to matter to you. The upstream CI treats the label as identity, so it is a stable contract by design.
- **The baked entrypoint is optional.** It does three things: hydrate the image-managed home files, mirror bb's log files to stdout, and run bb with SIGTERM forwarding for a clean stop. A derived image that overrides `ENTRYPOINT` silently skips the hydration and the log mirroring (bb writes its service output to files and never to stdout). Two softeners: the image home is pre-hydrated at build time, so a NEW home volume seeded from the image carries the managed rc blocks even if hydration never re-runs; and the only content hydration is there to *update* is the files whose hashes the image has shipped (`managed.tsv`). If your derived image overrides the entrypoint, hydration versions stop ticking on your volumes — either chain to `/home/developer/entrypoint.sh` from your own script, or accept that trade deliberately.
- **The hydration registry has no username in it.** Managed targets are `.bb/AGENTS.md`, `.bashrc`, `.zshrc` — home-relative paths. Renaming the image user (`usermod -l <new> -d <new home> -m developer`) therefore does not corrupt it; ownership is by uid 1000, so the baked content and the check invariants move with the rename. This is an upstream invariant worth keeping, and it is why the rename pattern described here keeps working across digests.
- **Cache and data paths are declared twice, on purpose.** The global mise config for every variant declares `npm_config_cache`, the pnpm store-dir (both `pnpm_config_*` and `npm_config_*` prefixes, so repo-pinned pnpm 9.x through 12.x land the same way), `CARGO_HOME`, `GOPATH`/`GOMODCACHE`/`GOCACHE`, and `UV_CACHE_DIR` — and the foundation image bakes the same keys as plain ENV so they hold for any exec context, shell or not. The mise copies are `{{ env.HOME }}`-relative and resolved per container, so a derived image that renames the user keeps correct paths inside mise-managed shells and shim invocations (the ENV copies keep the baked default home and are wrong there; redeclare them if you need them outside mise after a rename — pAIr00t's compose does exactly that). The point is predictability for sandbox policies: every path is checkable config, not per-tool probe noise ([pnpm#9246](https://github.com/pnpm/pnpm/issues/9246) is the canonical nuisance). Add your own with `mise use` and the same ENV pattern.

If your derived image overrides `ENTRYPOINT`, `bb-app` alone is a complete replacement: hydration is the entrypoint's only state-mutating step, and the log mirroring is a convenience, not plumbing bb needs. `~/.bb/logs/*` files still show up wherever the derived image points at them.
