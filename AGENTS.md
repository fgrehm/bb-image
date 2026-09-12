# bb-image

Container image for running [bb](https://getbb.app). `README.md` describes it for users; this file is the working context for agents.

## Layout

- `Containerfile` — the image. Debian 13 pinned by digest, mise, then node, bb, and Playwright with Chromium at build time.
- `mise.toml` — the image's toolset, installed as the global mise config at `/opt/mise/config.toml`.
- `scripts/entrypoint.sh` — PID 1 for the default command. Runs bb behind a log tail and forwards signals.
- `Makefile` — `build`, `hack`, `run`, `release`.
- `.github/workflows/publish.yml` — builds and pushes to GHCR on `main` and `v*` tags. On a tag it emits both axes: the bb version from the Containerfile and `img-<tag>` for the image itself.

Nothing heavy lives in `$HOME`. The toolchain is at `/opt/mise`, the npm cache at `/opt/npm-cache`, and Playwright's browsers at `/opt/ms-playwright`.

## Commands

- `make build` builds `bb:dev`. Layers are cached, so a `mise.toml`-only change is quick.
- `make hack` opens a shell in the image, with the same volume as `run`.
- `make run` serves bb with persistent state.

There is no test suite. Verification means building the image and exercising it.

## Design decisions worth not undoing

- **Everything the image owns stays out of `$HOME`.** Home is volume-backed at runtime, and a named volume is seeded from the image exactly once, so an image-owned file under home freezes at first boot and shadows later image updates. That is why the toolset, mise's data dir, the npm cache, and the Playwright browsers are all under `/opt`.
- **The toolset is the *global* mise config, aimed there by `MISE_GLOBAL_CONFIG_FILE`, not the system config at `/etc/mise`.** The same file under `/etc/mise` reads perfectly well and looks tidier, but mise only creates bootstrap shims for tools it picks up from the user and project scope. Under `/etc/mise`, node and bb get shims, every lazy tool silently gets none, and first-use installation stops working with no error anywhere. This cost an afternoon once.
- **Only cheap tools are left to first use.** The toolchain is in the image rather than on a volume, so a runtime-installed tool is gone once the container is recreated and is re-fetched on next use. Expensive things (node, bb, Playwright's browsers) are baked instead.
- **Layer order is load-bearing.** `COPY mise.toml` sits third from last on purpose. node, bb, and Playwright are installed above it, from `NODE_VERSION`, `BB_VERSION`, and `PLAYWRIGHT_VERSION`, so only the layers at or below the `COPY` depend on the toolset, and those are cheap. Moving the `COPY` earlier makes every toolset edit re-download everything.
- **`NODE_VERSION` is duplicated on purpose.** It appears both here and in `mise.toml`, because a layer cannot both install node and depend on the file that declares it. A build step asserts the two agree and fails with a readable message; bumping it in only one place fails the build rather than shipping a mismatch.
- **Agent CLIs and prek stay unpinned** (`version = "latest"`) so a fresh container resolves the current release. node, bb, and Playwright are pinned because they are baked.
- **`WORKDIR` is `$HOME`, not a single mount point**, because bb hosts many projects and resolves them by path.
- **One volume, the whole home directory** (`bb-home`). Provider logins, git config, ssh keys, shell history, and bb state all persist with no per-CLI mount list. It is seeded from the image on first creation, and it stays small only because nothing heavy is in `$HOME`.
- **`--userns=keep-id` is required for bind mounts under rootless podman.** Without it, container uid 1000 maps to a subuid and writes to a mounted project fail with permission denied.
- **The entrypoint exists for signals.** bb sends service output to files and never to stdout, so the obvious implementation is `exec tail -F` as PID 1, which means `podman stop` SIGKILLs bb. Instead the entrypoint backgrounds bb, tails the logs, and forwards SIGTERM so bb shuts down cleanly and exits 0. It deliberately does no reshimming: the shim farm is in the image at `/opt/mise/shims`, never shadowed by a volume, so there is nothing to reconcile.

## Rules that are easy to break

- npm gates native-addon install scripts. bb is broken without `--allow-scripts=@parcel/watcher,better-sqlite3,node-pty`; it installs cleanly and fails at runtime otherwise.
- In the entrypoint, a trapped signal makes `wait` return early with a status above 128, before the child has exited. The wait loop exists so bb's real exit code reaches the container. Removing it makes `podman stop` report 143 instead of 0.
- Editing `mise.toml` should rebuild only the last three layers. If a toolset edit re-downloads node, reinstalls bb, or re-fetches Chromium, the `COPY mise.toml` has drifted upward.
- npm's cache has to stay outside home. `npm_config_cache` redirects it, and `/opt/npm-cache` has to exist and be owned by the user, or `npm install -g` fails with EACCES on `/opt`.
- Playwright's browsers need `PLAYWRIGHT_BROWSERS_PATH` to point at `/opt/ms-playwright`, and the directory has to be owned by the user, or the download lands in the home volume and gets copied on every fresh volume.
- `BB_VERSION` in the `Containerfile` pins bb, and the publish workflow reads it from there to keep the tag and the baked version in step. The image's own version comes from the git tag, so bb tags and image tags stay on separate axes.
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

Home should stay near 28K. If it grows, something is writing build residue into `$HOME` that the home volume will copy on first boot:

```bash
podman run --rm bb:dev du -sh /home/developer
```

Check that shutdown is still clean:

```bash
podman run -d --name bbtest -p 39999:38886 --userns=keep-id bb:dev
podman stop -t 20 bbtest   # then confirm exit code 0, not 143 or 137
```

## Testing etiquette

Name test containers (`--name bbtest`) and remove them explicitly. A container left running holds its published port, which makes the next run fail to bind while something else answers on that port, and `podman ps --filter name=bb` is a substring match that will happily show you an unrelated `bb-yard-*` container. Use exact names or inspect the container by ID when checking status. Also check the port is free before concluding a run failed for another reason.
