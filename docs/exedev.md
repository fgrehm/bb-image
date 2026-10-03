# Running on exe.dev

The `exedev` flavor derives from the systemd `vm` image, keeps `bb.service`, and installs SSH tooling. The guest `ssh.service` and `ssh.socket` are disabled for now while checking whether exe.dev supplies SSH access itself. The image does not declare `EXPOSE 3000` or the `exe.dev/login-user` label. exe.dev uses Dockerfile `EXPOSE` metadata to select the default HTTP proxy target, so omitting it avoids automatically routing the root hostname to bb. The service still listens on port 3000 inside the VM; configure that proxy target explicitly when desired, and keep it private unless you deliberately make it public.

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

The expected access and API checks are:

```bash
ssh my-bb.exe.xyz
id
sudo -n true  # when logged in as developer
systemctl status bb.service
ss -ltnp | grep ':3000'
curl -fsS http://127.0.0.1:3000/api/v1/hosts
```

Configure the root HTTP proxy target explicitly before testing HTTPS access:

```bash
ssh exe.dev share port my-bb 3000
```

Then open `https://my-bb.exe.xyz/api/v1/hosts` in a browser authenticated for the VM's private proxy. An unauthenticated `curl` is not a reliable bb health check; the loopback command above checks bb independently of proxy authentication.

**Integration check still required:** verify that SSH login works with exe.dev's host-provided access while the guest SSH service is disabled and without the `exe.dev/login-user` label. If either assumption is wrong, revisit the guest SSH unit and label. The image currently leaves a `developer` linger marker; systemd linger starts that user's service manager at boot and keeps it running without an interactive login. Confirm whether exe.dev needs that user-session behavior. Also confirm which guest account SSH selects: passwordless sudo is granted to `developer`, not an arbitrary platform-created account. The image supplies that grant from first boot, so an unprivileged `developer` login needs neither a password nor a root-only enable command to administer the guest.

The proxy is private by default. `EXPOSE` controls automatic default-port selection; it is not a firewall. Removing it does not block the listener: exe.dev also proxies alternate ports 3000–9999 to users who have access to the VM. See the [exe.dev proxy docs](https://exe.dev/docs/proxy) before treating this as a network boundary.

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
- `developer` can use passwordless guest sudo without setting a password; no shared password is baked in
- `openssh-server` tooling is installed, but its guest service and socket are disabled
- no `EXPOSE 3000` declaration or `exe.dev/login-user` label is baked into the image; configure the proxy target explicitly if needed
- the VM's persistent disk preserves `/home/developer`, bb state, credentials, and project files

SSH host keys are removed during the build and are not baked into the OCI image. The `developer` account remains the account for project work, so bb, mise, and provider state remain together under its home directory.

`exedev` is intentionally separate from `vm`. The base VM flavor includes the shared SSH client but does not install an SSH server, because smolvm does not need one. `exedev` keeps bb listening on port 3000 rather than the local smolvm smoke-test port 38886; without `EXPOSE`, the root HTTP proxy target must be set explicitly.

## Persistence and lifecycle

The exe.dev VM has a persistent disk, so bb state and home-directory changes survive VM restarts. Sudoers and password changes under `/etc` persist on that disk too. Setting a password alone leaves the `NOPASSWD` grant active; replacing it with password-required sudo needs a validated policy and a working administrative access path. Guest root can access credentials and files placed inside the VM. The image does not create or schedule backups. Use the baked `bb-backup` tool and configure a backup destination separately if you need recovery archives.

The standard VM flavors remain the right choice for local smolvm use. Use `exedev` when exe.dev supplies the VM, persistent disk, SSH access, and HTTPS proxy. Real exe.dev creation and SSH access remain unverified integration checks.

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

The container checks inspect the image's files, labels, unit symlinks, and bb unit without requiring systemd in the check container. The host gate boots the image under smolvm and exercises the systemd and bb service contract:

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
