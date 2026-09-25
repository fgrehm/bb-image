# Running on exe.dev

The `exedev` flavor is the exe.dev adapter for the systemd VM image. It keeps the `vm` toolchain and `bb.service`, adds an SSH daemon, declares `developer` as the exe.dev login user, and serves bb on port `3000` for exe.dev's HTTPS proxy.

Create a VM from the published image:

```bash
ssh exe.dev new \
  --name my-bb \
  --image=ghcr.io/fgrehm/bb:edge-exedev
```

Then reach bb through the VM's private HTTPS endpoint:

```text
https://my-bb.exe.xyz/
```

The endpoint is private by default. Make it public only when the application is intended to be public:

```bash
ssh exe.dev share set-public my-bb
```

The image uses `/usr/local/bin/init` as PID 1. The wrapper prepares `/run/systemd` and cgroup v2 before executing `/sbin/init`; systemd runs as root, while `bb.service` runs as `developer`. SSH host keys are generated per VM and are not baked into the OCI image.

`exedev` is intentionally separate from `vm`. The base VM flavor does not install or run an SSH daemon, because smolvm does not need one. `exedev` also uses port `3000`, which exe.dev's proxy forwards by default, rather than the local smoke-test port `38886`.

For a private registry image, pass registry credentials at VM creation:

```bash
ssh exe.dev new \
  --name my-bb \
  --image=ghcr.io/fgrehm/bb:edge-exedev \
  --registry-auth=USERNAME:TOKEN
```

The image itself is public in the default GHCR setup, so this is only needed for a private derivative or registry.

Build and run the image checks before publishing:

```bash
make ci FLAVOR=exedev TAG=exedev
```

The normal flavor checks run in a container without a system manager, so they inspect the image's unit symlinks and files offline. The exe.dev host itself supplies the real VM boot, SSH access, persistent disk, and HTTPS proxy. References:

- [exe.dev custom images](https://exe.dev/docs/customization)
- [exe.dev private images](https://exe.dev/docs/private-image)
- [exe.dev HTTP proxies](https://exe.dev/docs/proxy)
