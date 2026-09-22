# bb-image

Container image for running [bb](https://getbb.app) rootless with your projects and persistent state. Published at `ghcr.io/fgrehm/bb`.

## Choose an image

| Flavor | Tags | Includes |
| --- | --- | --- |
| Full (default) | `latest`, `edge`, `0.43.4`, `img-0.3.2` | bb, Node.js, Playwright + Chromium, dev tools, DB and document tools, backups |
| Slim | `slim`, `edge-slim`, `0.43.4-slim`, `img-0.3.2-slim` | bb, Node.js, mise, lazy pnpm and agent CLIs, without Chromium or dev tools |
| Slim with sudo | `edge-slim-sudo`, `0.43.4-slim-sudo`, `img-0.3.2-slim-sudo` | Slim plus passwordless container sudo |
| Full with sudo | `edge-full-sudo`, `0.43.4-full-sudo`, `img-0.3.2-full-sudo` | Full plus passwordless container sudo |

Full keeps unsuffixed tags. `latest` and `slim` are moving aliases; sudo flavors have no bare moving aliases. Sudo operates inside the rootless container, but requires dropping `no-new-privileges`. See [running and security options](docs/running.md) and [tag policy](docs/publishing.md).

## Run it

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
- [Running as a microVM](docs/smolvm.md): the [smolvm](https://smolmachines.com) example.
- [Publishing](docs/publishing.md): tags, release workflow, and architecture support.
- [Changelog](CHANGELOG.md): changes to the image itself.

The image's toolset and browser downloads live outside the home volume. Runtime caches and logins live in it; managed home files update on startup without replacing your edits. See [home hydration](docs/tooling.md#home-hydration) for details.
