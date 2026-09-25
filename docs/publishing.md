# Publishing

[The publish workflow](../.github/workflows/publish.yml) builds on every push to `main` and on `v*` tags, runs `make check` against the built image, and only then pushes to GHCR, so a failing check blocks every publish. A `main` push that only touches documentation, meaning markdown, `examples/`, `LICENSE` or `.gitignore`, skips the build entirely, since none of it reaches the image. Tag pushes are never filtered, so a release always builds even when the tagged commit is documentation-only. There are two version axes: the bb release baked into the image, read from `BB_VERSION` in the Containerfile so a tag can never disagree with what is inside, and the image's own version, taken from the git tag. The second exists so that an image-only change, such as a node bump or a refreshed base digest, has somewhere to go without a bb release.

Run `make release VERSION=0.3.3` with the next image version to tag and push, which is what runs the workflow. The tag is signed (`git tag -s`, in whatever format your git config declares) and its message records the bb version, so `git tag -n1` answers which bb is in which image without opening the Containerfile.

| Ref | Tags |
| --- | --- |
| `main` | `edge`, plus `edge-slim`, `edge-slim-sudo`, `edge-full-sudo`, `edge-vm`, `edge-vm-sudo`, and `edge-exedev` |
| Stable `v0.4.0` with `BB_VERSION=0.44.0` | `0.44.0`, `0.44`, `img-0.4.0`, `latest`, plus suffixed pins for each non-full flavor |
| Prerelease `v0.4.0-rc1` | `img-0.4.0-rc1` and the corresponding suffixed image pins only |

In this example, `:0.44.0` follows images carrying bb 0.44.0, while `:img-0.4.0` pins one image release.

The bb tags follow the newest image for that bb release, so a node bump or a base digest refresh republishes them and anyone on `:0.44.0` picks the fix up. Pin `:img-<version>` when you want one specific build rather than one specific bb release. A prerelease tag publishes only the full and flavor-suffixed `img-` pins, so an rc cannot move the bb aliases, `latest`, or `slim`. Full keeps unsuffixed tags; the other flavors use `-slim`, `-slim-sudo`, `-full-sudo`, `-vm`, `-vm-sudo`, and `-exedev`. The VM and exe.dev flavors have no bare moving aliases.

It publishes to GHCR as `ghcr.io/fgrehm/bb` using the built-in `GITHUB_TOKEN`, so there are no secrets to configure. That name is set by `IMAGE_NAME` in the workflow; it does not follow the repo name, which is `bb-image`.

For Docker Hub, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets, change the login step to `docker/login-action` with `registry: docker.io` and those credentials, and change `IMAGE_NAME`.

The image is built for `linux/amd64` only. `linux/arm64` is untested: `node-pty` and `better-sqlite3` fall back to `node-gyp` when no prebuild matches, and that needs `python3` at build time, which the image deliberately does not carry at that stage. Add `linux/arm64` to `PLATFORMS` only after verifying a build.
