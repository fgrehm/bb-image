# bb-image

Container and VM images for running [bb](https://getbb.app) with development tools and persistent state. Published at `ghcr.io/fgrehm/bb`, supported on **Linux amd64 (`linux/amd64`)** for every flavor and **Linux arm64 (`linux/arm64`)** for the container flavors (`full`, `slim`, `worker`).

## Quick start

With [rootless Podman](https://podman.io/docs/installation) installed, run the published full image. No repository checkout or local build is needed:

```bash
podman run -d --name bb \
  --userns=keep-id \
  --security-opt no-new-privileges \
  -p 127.0.0.1:38886:38886 \
  -v bb-home:/home/developer \
  ghcr.io/fgrehm/bb:latest
```

Open [http://localhost:38886](http://localhost:38886). The port is local-only, and the `bb-home` volume keeps bb state, provider logins, Git/SSH configuration, and shell history when you replace the container.

To work on existing projects, add a bind mount to the command above, using an existing host directory:

```bash
-v "$HOME/src:/home/developer/src:Z"
```

View startup logs with `podman logs -f bb`. See [Running bb](docs/running.md) for Docker differences, port options, host credentials, and custom DNS or reverse proxies.

## Choose an image

Start with **full** unless you need a smaller server, a VM, or a separate execution worker.

| Flavor | Use it when you want… | Guide |
| --- | --- | --- |
| `full` (default) | bb with Playwright/Chromium, developer tools, database clients, and document tools | [Containers](docs/running.md) |
| `slim` | bb and lazy agent CLIs, without Chromium or the full development toolset | [Containers](docs/running.md) |
| `vm` | Full in a systemd microVM, with `bb.service` and rootless Podman | [smolvm](docs/smolvm.md) |
| `exedev` | The VM environment adapted for exe.dev's SSH access and HTTPS proxy | [exe.dev](docs/exedev.md) |
| `worker` | A separate execution container with Chromium and lazy agent CLIs, but no bb server | [Workers](docs/workers.md) |
| `worker-vm` | The worker environment with systemd and rootless Podman | [Workers](docs/workers.md) |

Every flavor includes Node.js, mise, Git, SSH client tooling, sudo, and backup utilities. Some tools are baked into the image; others install on first use. See [Tools and home state](docs/tooling.md) for availability and project-specific version pins. Workers require manual enrollment with a bb server.

VM flavors boot systemd and use a persistent machine disk, not the container launch command above. For smolvm, use the default VM-grade workload profile rather than `--unprivileged`. Both VM flavors bind bb to `127.0.0.1` by default, so the local smoke examples publish a `13xxx` host port and anything reaching bb from outside, including the exe.dev proxy, needs the listener opt-in in [The VM listener](docs/running.md#the-vm-listener). On exe.dev, SSH connects as `developer`; configure the proxy target explicitly as described in its guide.

## Choose a tag

All tags use the registry prefix `ghcr.io/fgrehm/bb:`.

| Tag | Meaning |
| --- | --- |
| `latest`, `slim` | Latest stable full or slim image |
| `edge`, `edge-<flavor>` | Builds from `main`; full uses unsuffixed `edge` |
| `img-<image-version>` | One image release, regardless of the bb version it carries |
| `<bb-version>`, `<bb-major>.<bb-minor>` | Newest image carrying that bb release or release line; image dependencies can change |

For non-full release tags, append the flavor: `img-<image-version>-vm` or `<bb-version>-slim`. VM, exe.dev, and worker flavors have no bare moving aliases. Use an image-version tag for a specific image release; see [Publishing](docs/publishing.md) for the full tag policy and [Releases](https://github.com/fgrehm/bb-image/releases) for available versions.

## Operational essentials

- **Persistence and backups:** Container home lives in `bb-home`; VM state lives on the machine disk. Toolchains live outside container home, so runtime-installed tools are lost when a container is replaced. Every flavor ships `bb-backup`, but no backup schedule is configured. See [persistence](docs/running.md#what-persists) and [backups](docs/backups.md).
- **Elevation:** Every flavor initially grants `developer` passwordless sudo. The quick start and standard Makefile container launches block elevation with `no-new-privileges`; VM workloads permit guest sudo. Use `sudo bb-set-password` to require a password where elevation is permitted. See [sudo setup and recovery](docs/sudo.md) before changing this policy.
- **bb updates:** Server flavors support in-app updates stored in persistent home state. Updating bb this way does not replace the image or its launcher. Back up first; `bb-app start --bundled` selects the installed launcher's bundled version. See [updating bb](docs/running.md#updating-bb-within-an-image).
- **Managed home files:** Startup updates unmodified image-managed agent guidance and shell blocks while preserving your edits. See [home hydration](docs/tooling.md#home-hydration).

## Build and verify locally

From a checkout of this repository, with Podman and Make installed:

```bash
make ci     # build and verify the full image
make run    # serve the local image at http://localhost:38886
make hack   # open a shell with the same home volume
```

To build another flavor, use `make ci FLAVOR=slim TAG=slim`. Mount projects when launching with `make run MOUNTS='-v ~/src:/home/developer/src:Z'`.

For repository changes, read [AGENTS.md](AGENTS.md) for build invariants, verification, and release conventions. Deployment details belong in the linked guides.

## More guides

- [Extend the image](docs/derived-images.md): tool installs, ownership, cache paths, and startup contracts.
- [Develop bb itself](docs/developing-bb.md): run bb from a source checkout using the full image.
- [Publish an image release](docs/publishing.md): build/check workflow, tags, and architecture support.
- [Changelog](CHANGELOG.md): user-visible changes to these images.
