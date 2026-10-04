# Publishing

[The publish workflow](../.github/workflows/publish.yml) builds on every push to `main` and on `v*` tags, runs flavor-specific checks before pushing each image to GHCR. Each flavor is pushed independently after its own checks pass, so a failure in another matrix job can leave a partially updated set of tags; the GitHub Release and release summary wait for the full matrix to succeed. A `main` push that only touches documentation, meaning markdown, `examples/`, `LICENSE` or `.gitignore`, skips the build entirely. The managed `container/agents.md` does reach the image, so edits to it must accompany the hydration hash update in `container/managed-prev.tsv`, which triggers the build. Tag pushes are never filtered, so a release always builds even when the tagged commit is documentation-only. There are two version axes: the bb release baked into the image, read from `BB_VERSION` in `container/Containerfile.foundation` so a tag can never disagree with what is inside, and the image's own version, taken from the git tag. The second exists so that an image-only change, such as a node bump or a refreshed base digest, has somewhere to go without a bb release.

The workflow derives its six published flavors, tag suffixes, and host gates from `container/flavors.tsv`; it generates the bake targets and CI matrix from the same manifest. The graph has two internal layers: `foundation` provides shared Node.js, while `browser` adds Playwright and Chromium for full and worker descendants. Each matrix job runs `make check` for its own flavor. The repository-scope fragments (lint, gitleaks, the flavor graph, packages wiring, and launch-flag derivation) run once, in the full job, and the expensive behavioural checks are anchored to one image per lineage. The `vm`, `exedev`, and `worker-vm` jobs additionally run the rootless Podman gate under smolvm; `vm` and `exedev` also run the systemd boot gate.

Run `make release VERSION='<next-image-version>'` with the next image version to tag and push, which is what runs the workflow. The tag is signed (`git tag -s`, in whatever format your git config declares) and its message records the bb version, so `git tag -n1` answers which bb is in which image without opening the Containerfile.

| Ref | Tags |
| --- | --- |
| `main` | `edge`, plus `edge-slim`, `edge-vm`, `edge-exedev`, `edge-worker`, and `edge-worker-vm` |
| Stable `v0.4.0` with `BB_VERSION=0.44.0` | `0.44.0`, `0.44`, `img-0.4.0`, `latest`, plus suffixed pins for each non-full flavor |
| Prerelease `v0.4.0-rc1` | `img-0.4.0-rc1` and the corresponding suffixed image pins only |

In this example, `:0.44.0` follows images carrying bb 0.44.0, while `:img-0.4.0` pins one image release.

The bb tags follow the newest image for that bb release, so a Node.js bump, a base digest refresh, or another image change republishes them and anyone following that bb version picks the fix up. Pin `:img-<version>` when you want one specific build rather than one specific bb release. A prerelease tag publishes only the full and flavor-suffixed `img-` pins, so an rc cannot move the bb aliases, `latest`, or `slim`. Full keeps unsuffixed tags; the other flavors use `-slim`, `-vm`, `-exedev`, `-worker`, and `-worker-vm`. The VM and exe.dev flavors have no bare moving aliases.

It publishes to GHCR as `ghcr.io/fgrehm/bb` using the built-in `GITHUB_TOKEN`, so there are no secrets to configure. That name is set by `IMAGE_NAME` in the workflow; it does not follow the repo name, which is `bb-image`.

For Docker Hub, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets, change the login step to `docker/login-action` with `registry: docker.io` and those credentials, and change `IMAGE_NAME`.

Images are built and supported for `linux/amd64` only.
