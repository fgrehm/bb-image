# bb-image

OCI image family for running [bb](https://getbb.app) with projects and persistent state: rootless container flavors and systemd-based microVM flavors. Published at `ghcr.io/fgrehm/bb`.

## Choose an image

| Flavor | Tags | Includes |
| --- | --- | --- |
| Full (default) | `latest`, `edge`, `0.44.0`, `img-0.3.2` | bb, Node.js, Playwright + Chromium, dev tools, DB and document tools, backups |
| Slim | `slim`, `edge-slim`, `0.44.0-slim`, `img-0.3.2-slim` | bb, Node.js, mise, lazy pnpm and agent CLIs, without Chromium or dev tools |
| Slim with sudo | `edge-slim-sudo`, `0.44.0-slim-sudo`, `img-0.3.2-slim-sudo` | Slim plus passwordless container sudo |
| Full with sudo | `edge-full-sudo`, `0.44.0-full-sudo`, `img-0.3.2-full-sudo` | Full plus passwordless container sudo |
| VM | `edge-vm`, `0.44.0-vm`, `img-<version>-vm` | Full, systemd as PID 1, and bb as an enabled service, without sudo |
| VM with sudo | `edge-vm-sudo`, `0.44.0-vm-sudo`, `img-<version>-vm-sudo` | VM plus passwordless guest sudo |
| exe.dev | `edge-exedev`, `0.44.0-exedev`, `img-<version>-exedev` | VM plus SSH and exe.dev integration, with bb on port 3000 |

Full keeps unsuffixed tags. `latest` and `slim` are moving aliases; sudo, VM, and exe.dev flavors have no bare moving aliases. Sudo is opt-in and operates inside the rootless container or isolated VM guest. Container sudo requires dropping `no-new-privileges`; VM images require smolvm's default VM-grade workload profile rather than `--unprivileged`. The `exedev` flavor is for [exe.dev](https://exe.dev/docs/customization) and uses its own SSH/runtime integration. See [running and security options](docs/running.md), [running as a microVM](docs/smolvm.md), and [tag policy](docs/publishing.md).

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
- [Developing bb](docs/developing-bb.md): build and run bb from a checkout using `full-sudo`.
- [Running as a microVM](docs/smolvm.md): the systemd-based `vm` flavor and [smolvm](https://smolmachines.com) examples.
- [Running on exe.dev](docs/exedev.md): the SSH-enabled `exedev` flavor and exe.dev setup.
- [Publishing](docs/publishing.md): tags, release workflow, and architecture support.
- [Changelog](CHANGELOG.md): changes to the image itself.

The image's toolset and browser downloads live outside the home volume. Runtime caches and logins live in it; managed home files update on startup without replacing your edits. See [home hydration](docs/tooling.md#home-hydration) for details.
