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

`--security-opt no-new-privileges` is what `make run` and `make hack` pass for the standard `full` and `slim` container flavors. The `-sudo` container flavors omit it so setuid sudo can work. The base packages bring the standard Debian setuid binaries, including `su` and `mount`, and none of them is needed here, so this makes sure an agent cannot use them to reach container root. Drop the flag if you actually want `su` inside.

`--userns=keep-id` is not optional in practice. Rootless podman maps container uid 1000 to a subordinate uid by default, so anything the container writes to a bind mount lands owned by a subuid and you cannot touch it on the host. `keep-id` maps it back to your own uid, and files come out owned by you.

On Docker, `--userns=keep-id` does not exist. Rootful Docker already writes bind mounts as uid 1000, which is your user on most single-user Linux installs. With rootless Docker, check what your files look like before trusting it.

## What persists

One volume covers everything worth keeping: threads, projects, settings, the auth secret, provider logins, git config, ssh keys, and shell history. It is seeded from the image on first creation, which is where `~/.bb` and the shell config come from, and it stays small because nothing heavy lives in `$HOME`.

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
