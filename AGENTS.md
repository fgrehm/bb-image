# bb-image

Container image for running [bb](https://getbb.app). `README.md` describes it for users; this file is the working context for agents.

## Layout

- `Containerfile` — the image. Debian 13 pinned by digest, mise, then node and bb at build time.
- `mise.toml` — the image's toolset, installed as the global mise config at `~/.config/mise/config.toml`.
- `scripts/entrypoint.sh` — PID 1 for the default command. Runs bb behind a log tail and forwards signals.
- `Makefile` — `build`, `hack`, `run`.
- `.github/workflows/publish.yml` — builds and pushes to GHCR on `main` and `v*` tags. On a tag it emits both axes: the bb version from the Containerfile and `img-<tag>` for the image itself.

## Commands

- `make build` builds `bb:dev`. Layers are cached, so a `mise.toml`-only change is quick.
- `make hack` opens a shell in the image, with the same volumes as `run`.
- `make run` serves bb with persistent state.

There is no test suite. Verification means building the image and exercising it.

## Design decisions worth not undoing

- **`mise.toml` is installed as the global config** so that it loads without `mise trust`. Do not move it into the container's home or anywhere project-scoped: a project config containing `[settings]` or inline tables fails with an untrusted-config error. Because it is the global config, mounted projects can still override it.
- **Only tools bb needs to start belong at build time** (currently just `node`). Everything else stays `lazy = true`, which is what keeps the image small. Note `mise reshim` creates shims only for installed tools and for lazy ones, so a non-lazy, not-installed tool gets no shim and will not be on `PATH`.
- **Layer order is load-bearing.** `COPY mise.toml` sits second to last on purpose. node and bb are installed above it, from `NODE_VERSION` and `BB_VERSION` in this file, so only the layers at or below the `COPY` depend on the toolset, and those are cheap. Moving the `COPY` earlier, or making the node install read the config, throws away the whole win and makes every toolset edit re-download node and reinstall bb.
- **`NODE_VERSION` is duplicated on purpose.** It appears both here and in `mise.toml`, because a layer cannot both install node and depend on the file that declares it. A build step asserts the two agree and fails with a readable message. Bumping node means changing both, and bumping it in only one place fails the build rather than shipping a mismatch.
- **Agent CLIs stay unpinned** (`version = "latest"`) so a fresh container resolves the current release.
- **`WORKDIR` is `$HOME`, not a single mount point**, because bb hosts many projects and resolves them by path.
- **State lives in named volumes** (`bb-state` for `~/.bb`, `bb-mise` for mise's data dir). Named volumes are seeded from the image on first creation, which is what puts the baked shims and node into `MISE_VOLUME`. An empty bind mount at either path leaves the container with no tools.
- **`--userns=keep-id` is required for bind mounts under rootless podman.** Without it, container uid 1000 maps to a subuid and writes to a mounted project fail with permission denied.
- **The entrypoint reshims on start.** A named volume is seeded from the image only once, so its shim farm is a snapshot and it shadows the image's. A tool added to a rebuilt image would install correctly but have no shim, leaving it unreachable, because a missing shim means there is nothing to invoke and therefore nothing to trigger the install. `mise reshim --force` costs about 20ms and reconciles the farm against the current config.
- **The entrypoint exists for signals.** bb sends service output to files and never to stdout, so the obvious implementation is `exec tail -F` as PID 1, which means `podman stop` SIGKILLs bb. Instead the entrypoint backgrounds bb, tails the logs, and forwards SIGTERM so bb shuts down cleanly and exits 0.

## Rules that are easy to break

- npm gates native-addon install scripts. bb is broken without `--allow-scripts=@parcel/watcher,better-sqlite3,node-pty`; it installs cleanly and fails at runtime otherwise.
- In the entrypoint, a trapped signal makes `wait` return early with a status above 128, before the child has exited. The wait loop exists so bb's real exit code reaches the container. Removing it makes `podman stop` report 143 instead of 0.
- Removing the `mise reshim` line from the entrypoint strands tools that were added to the image after a volume was created. The symptom is `command not found` for a tool that is genuinely installed and reachable via an absolute path.
- Editing `mise.toml` should rebuild only the last two layers. If a toolset edit re-downloads node or reinstalls bb, the `COPY mise.toml` has drifted upward in the `Containerfile`.
- `BB_VERSION` in the `Containerfile` pins bb, and the publish workflow reads it from there to keep the tag and the baked version in step. Bumping node reinstalls bb, since bb lives inside mise's node install. The image's own version comes from the git tag, so bb tags and image tags stay on separate axes.
- bb routes service output to `~/.bb/logs/*`. Anything that replaces the entrypoint must keep that visible.

## Releasing

Two version axes. The bb release comes from `BB_VERSION` in the Containerfile; the image's own version comes from the git tag, and the workflow reads both so a published tag cannot disagree with what is baked inside.

| Bump | Meaning |
| --- | --- |
| major | changes how the image is run: working directory, volume layout, ports |
| minor | new tools, a node or mise bump, a base digest refresh |
| patch | a bb version bump, or a fix that moves nothing else |

`make release VERSION=0.2.0` tags and pushes, which triggers the workflow. The tag message records the bb version so `git tag -n1` answers which bb is in which image without opening the Containerfile.

A prerelease suffix such as `0.3.0-rc1` publishes `img-0.3.0-rc1` and nothing else. The bb aliases and `latest` are gated on stable tags, because otherwise an rc would silently become what people pull.

## Verifying a change

```bash
make build
podman run --rm bb:dev /bin/bash -c 'node --version; bb --version; pwd'
podman run --rm bb:dev /bin/bash -c 'ls ~/.local/share/mise/shims | grep -E "^(go|claude)$"'
```

First-use installs are the most likely thing to regress. Exercise one directly:

```bash
podman run --rm bb:dev /bin/bash -c 'go version'
```

Check that a runtime install survives into a new container, and that shutdown is clean:

```bash
podman run --rm -v bb-mise:/home/developer/.local/share/mise bb:dev /bin/bash -c 'go version'
podman run -d --name bbtest -p 39999:38886 --userns=keep-id bb:dev
podman stop -t 20 bbtest   # then confirm exit code 0, not 143 or 137
```

## Testing etiquette

Name test containers (`--name bbtest`) and remove them explicitly. A container left running holds its published port, which makes the next run fail to bind while something else answers on that port, and `podman ps --filter name=bb` is a substring match that will happily show you an unrelated `bb-yard-*` container. Use exact names or inspect the container by ID when checking status. Also check the port is free before concluding a run failed for another reason.
