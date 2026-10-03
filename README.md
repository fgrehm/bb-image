# bb-image

OCI image family for running [bb](https://getbb.app) with projects and persistent state: rootless container flavors and systemd-based microVM flavors. Published at `ghcr.io/fgrehm/bb`.

## Choose an image

All flavors share sudo (initially passwordless for `developer`), `bb-backup`, `age`/`age-keygen`, the SQLite CLI and development files, and the common shell, Git, SSH client, archive, and mise tooling. Images are built and supported for `linux/amd64` only. See [tool availability](docs/tooling.md#shared-foundation).

| Flavor | Tags | Includes |
| --- | --- | --- |
| Full (default) | `latest`, `edge`, `0.44.0`, `img-0.4.0` | bb, Node.js, Playwright + Chromium, dev tools, DB and document tools, backups |
| Slim | `slim`, `edge-slim`, `0.44.0-slim`, `img-0.4.0-slim` | bb, Node.js, mise, lazy pnpm and agent CLIs, without Chromium or dev tools |
| VM | `edge-vm`, `0.44.0-vm`, `img-0.4.0-vm` | Full, systemd as PID 1, bb service, rootless Podman CLI, initial passwordless guest sudo |
| exe.dev | `edge-exedev`, `0.44.0-exedev`, `img-0.4.0-exedev` | VM plus exe.dev integration and rootless Podman CLI; guest SSH is disabled pending access validation |
| Worker | `edge-worker`, `0.44.0-worker`, `img-0.4.0-worker` | Node.js, mise, lazy agent CLIs, Playwright + Chromium, backups; no bb server or enrollment |
| Worker VM | `edge-worker-vm`, `0.44.0-worker-vm`, `img-0.4.0-worker-vm` | Worker plus systemd, rootless Podman CLI, and backups for manually enrolled execution machines; no bb server or enrollment |

Full keeps unsuffixed tags. `latest` and `slim` are moving aliases; VM, exe.dev, and worker flavors have no bare moving aliases. All flavors initially grant passwordless sudo. Standard Makefile container launches block it with `no-new-privileges`; use `make run FLAVOR=full SECURITY_OPTS=` to permit container elevation on any container flavor. Direct engine launches must pass the no-new-privileges flag explicitly to block elevation. VM images permit guest sudo and require smolvm's default VM-grade workload profile rather than `--unprivileged`. Use `sudo bb-set-password` to require a password, as described in [sudo setup and recovery](docs/sudo.md). These changes are [Unreleased](CHANGELOG.md#unreleased); older pinned tags retain their original policy. The `exedev` flavor is for [exe.dev](https://exe.dev/docs/customization); it keeps guest SSH disabled and does not set the default proxy port until exe.dev access is verified. See [running and security options](docs/running.md), [running as a microVM](docs/smolvm.md), and [tag policy](docs/publishing.md).

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
