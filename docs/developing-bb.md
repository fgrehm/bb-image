# Developing bb

`full-sudo` is the contributor environment. It contains packaged bb, but the example below keeps the container running with `sleep infinity` rather than starting that server; you start source-built bb from the mounted checkout. To run packaged bb alongside it, launch a separate container. No bb source is baked into any image.

```bash
make ci FLAVOR=full-sudo TAG=full-sudo
# Pass the token through the environment, not on podman's command line.
export MISE_GITHUB_TOKEN="$(gh auth token)"
podman run -d --name bb-dev \
	--userns=keep-id \
	--env MISE_GITHUB_TOKEN \
	-v ~/src/bb:/home/developer/src:Z \
	-v bb-dev-home:/home/developer \
	bb:full-sudo sleep infinity
podman exec -it bb-dev bash
```

Inside the container, run `cd ~/src` to enter the mounted checkout, then:

1. `mise install python pnpm` — one-time. `pnpm` works lazy, but node-gyp resolves `python3` on PATH, which is mise's lazy shim, so a fast python has to be installed into mise first. Mise uses `MISE_GITHUB_TOKEN` for first-use installs on a rate-limited IP; no scopes are required.
2. `pnpm install` — the checkout's `packageManager` field (pnpm@9.15.0 today) is authoritative; the native modules (better-sqlite3, node-pty, @parcel/watcher) compile against the image's build toolchain.
3. `pnpm dev` for the development loop, or `pnpm start:worktree` to exercise the production-style serving path. Each checkout gets its own data directory under `~/.bb-dev/<checkout-instance>/` and deterministic high ports derived from the checkout path, so it runs alongside a packaged bb instance without touching its state. The launcher prints its ports.

Sudo matters here because the vendor agents and package installs inside the checkout may want apt packages; the container is still rootless, so host access stays bounded by the container itself.

There is no separate `bb:source` variant. `full-sudo` was proven against a real checkout (install, native compile, dev boot) and the smaller focused image would duplicate its build prerequisites without saving anything that matters.
