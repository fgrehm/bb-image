# Running on exe.dev

The `exedev` flavor is the exe.dev adapter for the systemd VM image. It keeps the `vm` toolchain and `bb.service`, adds an SSH daemon, declares `developer` as the exe.dev login user, and serves bb on port `3000` for exe.dev's HTTPS proxy.

Create a VM from the published image:

```bash
ssh exe.dev new \
  --name my-bb \
  --image=ghcr.io/fgrehm/bb:edge-exedev
```

For a reproducible deployment, use a pinned image-version tag instead:

```bash
ssh exe.dev new \
  --name my-bb \
  --image=ghcr.io/fgrehm/bb:img-<image-version>-exedev
```

The VM is reachable over SSH as `developer`:

```bash
ssh my-bb.exe.xyz
systemctl status bb.service
systemctl status ssh.service
ss -ltnp | grep ':3000'
curl -fsS http://127.0.0.1:3000/api/v1/hosts
```

From the host, exe.dev's private HTTPS proxy reaches the same bb service:

```bash
curl -fsS https://my-bb.exe.xyz/api/v1/hosts
```

The endpoint is private by default. Make it public only when the application is intended to be public:

```bash
ssh exe.dev share set-public my-bb
```

Set it back to private with:

```bash
ssh exe.dev share set-private my-bb
```

## What the image provides

The `exedev` flavor derives from the systemd `vm` flavor and adds the exe.dev integration:

- systemd runs as root at PID 1
- `/usr/local/bin/init` prepares `/run/systemd` and cgroup v2, then executes `/sbin/init`
- `bb.service` runs as `developer` and serves bb on port `3000`
- `openssh-server` is enabled for exe.dev SSH access
- `ssh-host-keys.service` generates per-VM host keys before `ssh.service`
- `exe.dev/login-user=developer` tells exe.dev which account to use
- the VM's persistent disk preserves `/home/developer`, bb state, credentials, and project files

SSH host keys are intentionally not baked into the OCI image. The `developer` account is also the account to use for project work, so bb, mise, and provider state remain together under its home directory.

`exedev` is intentionally separate from `vm`. The base VM flavor does not install or run an SSH daemon, because smolvm does not need one. `exedev` uses port `3000`, which exe.dev's HTTPS proxy forwards by default, rather than the local smolvm smoke-test port `38886`.

## Persistence and lifecycle

The exe.dev VM has a persistent disk, so bb state and home-directory changes survive VM restarts. The image does not create or schedule backups. Use the baked `bb-backup` tool and configure a backup destination separately if you need recovery archives.

The standard VM flavors remain the right choice for local smolvm use. Use `exedev` when exe.dev supplies the VM, SSH, persistent disk, and HTTPS proxy.

## Private images

The upstream `edge-exedev` and release images are public in GHCR, so no registry credentials are needed. If you publish a private derivative or use another private registry, pass credentials when creating the VM:

```bash
ssh exe.dev new \
  --name my-bb \
  --image=registry.example/your-org/bb:tag \
  --registry-auth=USERNAME:TOKEN
```

The registry credentials are used for the host-side image pull before the VM is created. Do not put the token in the image or in a committed file.

## Build and verify locally

Build and run the image checks before publishing:

```bash
make ci FLAVOR=exedev TAG=exedev
```

The container checks inspect the image's files, labels, unit symlinks, SSH host-key service, and bb unit without requiring systemd in the check container. The host gate boots the image under smolvm and exercises the same systemd, bb, SSH, and port-3000 contract:

```bash
make check-smolvm-systemd FLAVOR=exedev TAG=exedev
```

That gate is a compatibility smoke test, not a substitute for creating one real exe.dev VM. Live exe.dev creation, SSH login, HTTPS proxying, and persistence are the final integration checks.

## Cleanup

Remove the test VM when finished:

```bash
ssh exe.dev rm my-bb
```

References:

- [exe.dev custom images](https://exe.dev/docs/customization)
- [exe.dev private images](https://exe.dev/docs/private-image)
- [exe.dev HTTP proxies](https://exe.dev/docs/proxy)
