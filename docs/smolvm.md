# Running as a microVM

[smolvm](https://smolmachines.com) boots OCI images as libkrun microVMs with their own guest kernel. The dedicated `vm` flavor adds systemd as the workload's PID 1, runs bb through an enabled `bb.service`, and includes the rootless Podman CLI; it otherwise carries the same software as `full`, without sudo. Choose `vm-sudo` when the guest also needs passwordless package administration.

Use [`examples/smolvm-systemd/Smolfile`](../examples/smolvm-systemd/Smolfile) for the systemd VM. It follows `edge-vm` for testing; pin `img-<image-version>-vm` for a long-lived machine:

```bash
smolvm machine create --name bb --smolfile examples/smolvm-systemd/Smolfile
smolvm machine start --name bb
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:38886/api/v1/hosts   # 200
smolvm machine shell --name bb
smolvm machine exec --name bb -- systemctl status bb.service
```

The VM disk persists `/home/developer`, Podman images and containers, system state, caches, and machine identity across stop/start. systemd runs as root at PID 1 because it initializes and manages the guest; `bb.service` explicitly runs bb as uid/gid `developer`. The container-oriented `entrypoint.sh` is not PID 1 and is not used to start bb.

## Runtime profile

The example follows `edge-vm`. To use the elevated profile, copy it and change the image to `ghcr.io/fgrehm/bb:edge-vm-sudo` (or a pinned `img-<image-version>-vm-sudo`).

Use smolvm's default VM-grade image profile. Do not add `--unprivileged`: that option deliberately removes capabilities, writable cgroups, and mounts that init systems need. The microVM is the isolation boundary. The standard `vm` flavor has no sudo; `vm-sudo` grants passwordless root only inside the guest. Do not mount a container-engine socket or broad sensitive host paths into either flavor by default.

## Rootless Podman CLI

The `vm` family (`vm`, `vm-sudo`, and `exedev`) and the local `worker-vm` prototype include Podman for commands run as `developer`. There is **no Podman API socket or daemon endpoint**. The CLI uses rootless user namespaces and stores pulled images and containers under `/home/developer/.local/share/containers`; that storage persists on the VM disk and consumes its space. Check usage with `podman system df`; remove only data you no longer need with `podman system prune`.

A lingering `developer` systemd user manager supplies delegated cgroups, so rootless `--memory` and `--cpus` limits work. Podman is configured to use `slirp4netns` for rootless networking in smolvm. The image grants `developer` access to `/dev/net/tun` through a systemd tmpfiles rule; wait for `user@1000.service` to become active after boot before using Podman. No Podman API socket is enabled. Do not expose a socket or TCP API without a separate security decision; [Podman's API](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html) grants full control as the user running it.

The VM uses Debian 13's Podman 5 package. This is intentional: rootless `pasta` networking did not work in the smolvm guest, while `slirp4netns` did. Podman 6 removes `slirp4netns` ([upstream change](https://github.com/podman-container-tools/podman/pull/27828)), so changing the Podman major version or Debian base requires a successful rootless networking test first. The guest kernel also lacks swap-limit support; Podman can enforce a memory limit without a swap limit.

All systemd VM flavors use the repository's host gate. The exedev variant uses its own Smolfile and port 3000:

```bash
make ci FLAVOR=vm TAG=vm
make check-smolvm-systemd FLAVOR=vm TAG=vm
make check-smolvm-podman FLAVOR=vm TAG=vm

# The elevated profile has the same boot gate.
make ci FLAVOR=vm-sudo TAG=vm-sudo
make check-smolvm-systemd FLAVOR=vm-sudo TAG=vm-sudo
make check-smolvm-podman FLAVOR=vm-sudo TAG=vm-sudo

# The exe.dev adapter uses the same systemd smoke gate and checks bb on port 3000.
make ci FLAVOR=exedev TAG=exedev
make check-smolvm-systemd FLAVOR=exedev TAG=exedev
make check-smolvm-podman FLAVOR=exedev TAG=exedev
```

Each `make check-smolvm-systemd` invocation requires a host with smolvm and KVM/libkrun. It asserts systemd as workload PID 1, `multi-user.target`, bb service and API health, persistent home state, recovery after stop/start, and bounded shutdown. `make check-smolvm-podman` boots a separate disposable VM and checks rootless Podman, delegated cgroups, slirp networking, port publishing, and the absence of an API socket.

## Local image archive

A local archive skips the registry pull and is the fastest way to test an image build:

```bash
podman save bb:vm -o bb-vm.tar
smolvm machine create --name bb --smolfile examples/smolvm-systemd/Smolfile --image ./bb-vm.tar
```

## Networking and credentials

bb needs outbound access for provider APIs, Git, and package installs, so the example enables networking and publishes port 38886. The baked agent CLIs are intentionally unpinned; without a GitHub token, mise resolves them against GitHub's unauthenticated rate limit and can fail with an opaque 403.

smolvm secret references resolve per launch. Add this to a private copy of the Smolfile when token forwarding is needed:

```toml
[secrets]
GITHUB_TOKEN = { from_env = "GH_TOKEN" }
```

Then create the machine with a materialized host variable:

```bash
GH_TOKEN="$(gh auth token)" smolvm machine create --name bb --smolfile ./Smolfile
```

The reference, rather than the token value, is stored in the machine definition. An unset variable fails the launch instead of silently starting unauthenticated.

## Architecture and sandboxing

The published image is currently `linux/amd64` only. Matching the guest is automatic on x86_64 hosts; Apple Silicon requires `rosetta = true` in the Smolfile.

Bubblewrap works fully inside the microVM, including a fresh `/proc` mount with PID-namespace unsharing. The corresponding failure inside a nested rootless container is a container limitation and does not apply to the VM guest.

The `exedev` flavor is for exe.dev rather than smolvm. It adds exe.dev's init wrapper and bb's port-3000 service; guest SSH stays disabled pending verification of exe.dev-provided access. See [Running on exe.dev](exedev.md).

The older [`examples/smolvm/Smolfile`](../examples/smolvm/Smolfile) remains an example of booting the ordinary full container image directly, with `entrypoint.sh` as workload PID 1. Prefer the `vm` flavor when you want an init system, managed services, or future VM-native timers and worker enrollment.
