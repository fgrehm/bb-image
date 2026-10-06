# bb-image

OCI image family for running [bb](https://getbb.app) with projects and persistent state: rootless container flavors and systemd-based microVM flavors. Published at `ghcr.io/fgrehm/bb`.

## Choose an image

All flavors share sudo (initially passwordless for `developer`), `bb-backup`, `age`/`age-keygen`, the SQLite CLI and development files, and the common shell, Git, SSH client, archive, and mise tooling. Images are built and supported for `linux/amd64` only. See [tool availability](docs/tooling.md#shared-foundation).

The `edge` tags track `main`; stable version tags are published by a release. `latest` tracks full and `slim` tracks slim; other flavors have no bare moving aliases.

| Flavor | Tags | Includes |
| --- | --- | --- |
| Full (default) | `latest`, `edge`, `<bb-version>`, `img-<version>` | bb, Node.js, Playwright + Chromium, dev tools, DB and document tools, backups |
| Slim | `slim`, `edge-slim`, `<bb-version>-slim`, `img-<version>-slim` | bb, Node.js, mise, lazy agent CLIs and backups; no Chromium or full development toolset |
| VM | `edge-vm`, `<bb-version>-vm`, `img-<version>-vm` | Full with systemd, bb service, rootless Podman CLI and persistent VM state |
| exe.dev | `edge-exedev`, `<bb-version>-exedev`, `img-<version>-exedev` | VM plus exe.dev integration; SSH lands as `developer`, guest SSH stays disabled |
| Worker | `edge-worker`, `<bb-version>-worker`, `img-<version>-worker` | Node.js, Playwright + Chromium, mise, lazy agent CLIs and backups; no bb server or enrollment |
| Worker VM | `edge-worker-vm`, `<bb-version>-worker-vm`, `img-<version>-worker-vm` | Worker with systemd and rootless Podman CLI for manually enrolled execution machines |

Node.js is shared from the foundation layer, while the internal browser layer is shared by full, worker, and their descendants. Slim is intentionally a sibling without browser or full development packages, for deployments that value its smaller footprint over those tools. Every flavor includes `bb-backup`; workers can protect enrollment identity and agent traces without a bb server. Full keeps unsuffixed tags. `latest` and `slim` are moving aliases; VM, exe.dev, and worker flavors have no bare moving aliases. Release pins use the bb version, the bb minor (for example `0.45`), or `img-<version>`, each carrying the flavor's suffix. All flavors initially grant passwordless sudo. Standard Makefile container launches block it with `no-new-privileges`; use `make run FLAVOR=full SECURITY_OPTS=` to permit container elevation on any container flavor. Direct engine launches must pass the no-new-privileges flag explicitly to block elevation. VM images permit guest sudo and require smolvm's default VM-grade workload profile rather than `--unprivileged`. Use `sudo bb-set-password` to require a password, as described in [sudo setup and recovery](docs/sudo.md). These changes are documented in the [0.5.0 release notes](CHANGELOG.md); older pinned tags retain their original policy. The `exedev` flavor is for [exe.dev](https://exe.dev/docs/customization); host-provided SSH connects as `developer`, the guest SSH daemon stays disabled, and no default proxy port is set, so configure the proxy target explicitly. See [running and security options](docs/running.md), [running as a microVM](docs/smolvm.md), and [tag policy](docs/publishing.md).

Server flavors enable bb's in-app update channel. Updates install into persistent home state, so back up before applying one; `bb-app start --bundled` runs the baked version. `bb-image-info` reports baked Node, Playwright, and bb versions alongside the installed bb version where present. See [updating bb within an image](docs/running.md#updating-bb-within-an-image).

## Run it as a container

```bash
make ci     # build and verify the full image locally
make run    # serve bb at http://localhost:38886
make hack   # open a shell with the same home volume
```

`make run` uses a named `bb-home` volume for bb state, logins, git and shell config, and binds the port to `127.0.0.1`. Mount your projects with `MOUNTS`, for example:

```bash
make run MOUNTS='-v ~/src:/home/developer/src:Z'
```

Use `make ci FLAVOR=slim TAG=slim` to build and check another flavor. For direct Podman and Docker commands, port options, volume details, host logins, and security behavior, see [Running bb](docs/running.md).

## What else is here

- [Tools and home state](docs/tooling.md): baked and lazy tools, mise project pins, hydration, and operational gotchas.
- [Backups](docs/backups.md): recovery archives and additive trace mirroring with `bb-backup`.
- [Using this image as a base](docs/derived-images.md): ownership, tool installs, cache paths, and entrypoint contracts.
- [Developing bb](docs/developing-bb.md): build and run bb from a checkout using `full` with `SECURITY_OPTS=`.
- [Running as a microVM](docs/smolvm.md): systemd VM flavors, rootless Podman CLI, and [smolvm](https://smolmachines.com) examples.
- [Worker images](docs/workers.md): BB-free `worker` and `worker-vm` targets for manually enrolled execution machines.
- [Running on exe.dev](docs/exedev.md): the `exedev` flavor and its pending SSH/proxy integration checks.
- [Publishing](docs/publishing.md): tags, release workflow, and architecture support.
- [Changelog](CHANGELOG.md): changes to the image itself.

The image's toolset and browser downloads live outside the home volume. Runtime caches and logins live in it; managed home files update on startup without replacing your edits. See [home hydration](docs/tooling.md#home-hydration) for details.
