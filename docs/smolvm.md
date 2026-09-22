# Running as a microVM

[smolvm](https://smolmachines.com) boots images as libkrun microVMs with their own guest kernel. This image is consumed as-is, because a Smolfile's `image` field takes an OCI reference, a `podman save` archive, or an unpacked rootfs, so nothing needs repackaging.

[The Smolfile](../examples/smolvm/Smolfile) is a worked example pinned to image `img-0.2.0`. From the repository root, create and start a machine:

```bash
smolvm machine create --name bb --smolfile examples/smolvm/Smolfile
smolvm machine start --name bb
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:38886/api/v1/hosts   # 200
smolvm machine shell --name bb
```

A local archive skips the registry pull entirely, which is the offline path and also the faster one to iterate on:

```bash
podman save ghcr.io/fgrehm/bb:edge -o bb.tar
smolvm machine create --name bb --smolfile examples/smolvm/Smolfile --image ./bb.tar
```

Verified with smolvm 1.16.0 on Linux x86_64 with KVM: the entrypoint runs as PID 1, bb answers on the published port, Playwright's Chromium launches, and state survives `machine stop` and `machine start` (0.45s and 0.71s). Three details are worth knowing before you rely on it:

- **`bwrap` works fully here**, including the fresh `/proc` mount with PID-namespace unsharing that needs `--privileged` inside a container. That limitation is a container artifact and does not apply to a VM guest.
- **Keep `net = true`, and give the machine a token.** With networking off, mise cannot resolve the unpinned agent CLIs and logs a warning on every command (`MISE_OFFLINE=1` silences those). With networking on and no token it resolves them unauthenticated instead, against a limit of 60 requests per hour, and then fails with 403s that do not read as rate limiting. To enable token forwarding, uncomment the `[secrets]` block and `GITHUB_TOKEN` line at the bottom of the Smolfile first. smolvm resolves that reference per launch; once enabled, an unset variable fails the launch loudly rather than starting unauthenticated:

  ```bash
  GH_TOKEN="$(gh auth token)" smolvm machine create --name bb --smolfile examples/smolvm/Smolfile
  ```
- **The image is `linux/amd64` only.** Matching the guest is automatic on x86_64 hosts; on Apple Silicon it needs `rosetta = true`.

The VM's disk replaces the container's named volume: `~/.bb`, caches, and shell state live on the machine's storage disk and persist across `exec` and restarts, with no seed-on-first-boot semantics to reason about.
