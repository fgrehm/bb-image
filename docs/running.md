# Running bb

This guide covers the rootless container flavors. The `vm` and `vm-sudo` flavors boot systemd under smolvm instead; see [Running as a microVM](smolvm.md).

```bash
make build
make run     # serves bb on http://localhost:38886
make hack    # shell in the same environment
make check   # verify the built image
make ci      # build + verify in one target (what release CI runs)
```

bb's default port is 38886. If something else on your machine already owns it, pass another: `make run BB_PORT=39886`. It is published on `127.0.0.1` only, so it is not reachable from other machines; `make run BB_BIND=0.0.0.0` changes that, and then you should reach it by IPv4 address rather than `localhost` for the [rootless networking behavior](tooling.md#gotchas).

## The same thing without make

This uses the local `bb:dev` tag produced by `make build`. To use a published image instead, replace it with `ghcr.io/fgrehm/bb:latest`.

```bash
podman run -d --name bb \
  --userns=keep-id \
  --security-opt no-new-privileges \
  -p 127.0.0.1:38886:38886 \
  -v bb-home:/home/developer \
  -v "$HOME/src:/home/developer/src:Z" \
  bb:dev
```

Every image installs sudo and a passwordless grant for `developer`. Standard container profiles (`full`, `slim`, and `worker`) pass `--security-opt no-new-privileges` through `make run` and `make hack` (workers support only `make hack`), blocking setuid elevation, including sudo. The `-sudo` container flavors are retained as compatibility launch profiles with the same payload; Makefile omits the flag for them. It also blocks other setuid binaries such as `su` and `mount`. No `--privileged` flag is needed to permit sudo.

To opt into passwordless elevation with a standard container image, explicitly choose the launch policy:

```bash
make run SECURITY_OPTS=
make hack SECURITY_OPTS=
```

Direct Docker or Podman invocations choose their own policy: without `--security-opt no-new-privileges`, sudo works even on an unsuffixed image. The tag does not enforce the security setting. Guest/container root can access credentials and files shared into the environment, so keep sensitive host mounts and host container-engine sockets out of elevated environments.

Setting a user password does not disable the `NOPASSWD` rule. To require password authentication, first set a password and then replace the grant with a validated password-required sudoers policy, retaining administrative access. Container changes under `/etc` are not part of the home volume and disappear on recreation unless separately provisioned; [VM disk state](smolvm.md) persists them. No shared password or password-setup prompt is baked in.

`--userns=keep-id` is not optional in practice. Rootless podman maps container uid 1000 to a subordinate uid by default, so anything the container writes to a bind mount lands owned by a subuid and you cannot touch it on the host. `keep-id` maps it back to your own uid, and files come out owned by you.

On Docker, `--userns=keep-id` does not exist. Rootful Docker already writes bind mounts as uid 1000, which is your user on most single-user Linux installs. With rootless Docker, check what your files look like before trusting it.

## What persists

One volume covers everything worth keeping: threads, projects, settings, the auth secret, provider logins, git config, ssh keys, and shell history. It is seeded from the image on first creation, which is where `~/.bb` and the shell config come from, and the image seeds only a small initial home. Projects, databases, session traces, and runtime caches can grow the persistent volume substantially; monitor its usage and back it up.

| Mount | Holds | If you leave it out |
| --- | --- | --- |
| `bb-home:/home/developer` | bb state, provider logins, git and ssh config, history | All of it dies with the container and you re-login to every provider |
| `~/src:/home/developer/src` | Your code | bb has nothing to work on |

The toolchain is deliberately *not* on a volume. It lives in the image at `/opt/mise`, so it stays in step with the image instead of freezing at volume creation. The trade is that tools installed at runtime are per-container and re-fetched after a rebuild, which is why only cheap ones are left to first use.

## Reusing logins you already have on the host

Not required, since the home volume keeps its own logins. But if you would rather not sign in twice, mount the host's:

```bash
make run MOUNTS='-v ~/.config/git:/home/developer/.config/git \
                 -v ~/.ssh:/home/developer/.ssh \
                 -v ~/.claude:/home/developer/.claude \
                 -v ~/.claude.json:/home/developer/.claude.json \
                 -v ~/.codex:/home/developer/.codex \
                 -v ~/.config/gh:/home/developer/.config/gh \
                 -v ~/.pi:/home/developer/.pi \
                 -v ~/.omp:/home/developer/.omp'
```

Mounting the host's agent config means the container's CLI version writes state that your host CLI also reads. That is normally fine and occasionally not, so if a provider starts misbehaving, drop its mount and log in inside the container instead.
