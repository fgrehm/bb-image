# Running bb

This guide covers the rootless container flavors. The `vm` flavor boots systemd under smolvm instead; see [Running as a microVM](smolvm.md). [The VM listener](#the-vm-listener) applies to the VM flavors as well.

```bash
make build
make run     # serves bb on http://localhost:38886
make hack    # shell in the same environment
make check   # verify the built image
make ci      # build + verify in one target (what release CI runs)
```

bb's default port is 38886. If something else on your machine already owns it, pass another: `make run BB_PORT=39886`. It is published on `127.0.0.1` only, so it is not reachable from other machines; `make run BB_BIND=0.0.0.0` changes that, and then you should reach it by IPv4 address rather than `localhost` for the [rootless networking behavior](tooling.md#gotchas).

## Custom DNS and reverse proxies

bb 0.45.0 rejects requests with an unconfigured DNS hostname. Localhost and literal IP access still work. Before using a custom hostname, run this as `developer` in the deployment, using its actual public URL:

```bash
bb-app config set BB_APP_URL https://bb.example.com
```

Restart bb through its normal supervisor afterward (recreate the container with the same home volume, or restart `bb.service` in a VM). In a VM, `/etc/default/bb` can also supply `BB_APP_URL`, but `bb-app config set` wins whenever both are set: it writes `~/.bb/config.json`, which bb reads after the service environment. Matching proxy Host/Origin headers alone do not authorize an arbitrary hostname. `BB_BIND` only selects the container's host-side bind address, not an allowed request hostname. Do not bake a deployment URL into a shared image. See the [exe.dev setup](exedev.md) for its proxy hostname.

## The VM listener

The `vm` and `exedev` flavors start bb through `bb.service`, which reads bb's own listener variables instead of a command-line flag:

| File | Owner | Role |
| --- | --- | --- |
| `/etc/bb/listener.env` | image | default, `127.0.0.1` with port `38886` on `vm` and `3000` on `exedev` |
| `/etc/default/bb` | operator | optional override, read second, so its variables win |

systemd applies `EnvironmentFile=` entries in order and a later file wins per variable. Both files become the service environment, which is the weakest layer in bb's own precedence chain:

    service environment  <  CLI flag  <  ~/.bb/config.json  <  ~/.bb/env.json

So `bb-app env set BB_SERVER_BIND_HOST 0.0.0.0` also wins over `/etc/default/bb`. bb accepts only `127.0.0.1` or `0.0.0.0` for the host and a positive integer for the port; anything else fails at startup. Both are startup-only, so a change needs a restart:

```bash
printf 'BB_SERVER_BIND_HOST=0.0.0.0\n' | sudo tee -a /etc/default/bb
sudo systemctl restart bb.service
```

Loopback is the default because a VM has a platform gateway or a guest-side proxy in front of it, and both shapes prefer a loopback listener. Inside the guest, `http://127.0.0.1:38886` (or `:3000` on `exedev`) works either way. Nothing outside reaches it until you opt in: the smolvm `[dev] ports` mapping (host 13886 to the guest's 38886 in the examples), `exe.dev share port`, and a host `curl` to that published port all need a routable listener, which is the command above. A reverse proxy in the guest, such as Tailscale Serve, can only forward to `http://127.0.0.1`, which is why loopback is the default.

To put it back to loopback, delete the `BB_SERVER_BIND_HOST` line from `/etc/default/bb` and restart `bb.service`. If the value was set with `bb-app env set`, change it with `bb-app env set BB_SERVER_BIND_HOST 127.0.0.1` or delete the key from `~/.bb/env.json`, because that file outranks `/etc/default/bb`.

The listener and the request hostname are separate settings. `BB_SERVER_BIND_HOST` decides what bb listens on, `BB_BIND` in `make run` decides what the container publishes on the host, and `BB_APP_URL` decides which hostname bb accepts. See [Custom DNS and reverse proxies](#custom-dns-and-reverse-proxies).

Neither platform offers a verified way to install configuration before the first `bb.service` start. A deployment that needs a routable listener from the first boot bakes `/etc/default/bb` into a derived image; see [Using this image as a base](derived-images.md).

Container flavors are different and unchanged: the entrypoint starts bb on `0.0.0.0:38886`, so publishing a port is enough. `make run BB_PORT=3000` publishes `127.0.0.1:3000` on the host and forwards it to the container's 38886.

## Upgrading to bb 0.45.0

Take a [recovery backup](backups.md#explicit-backup-and-restore) before upgrading persistent state. Test with a disposable copy of the old state first; reverting the image tag against an already migrated database is not a safe rollback plan. Validate enrolled workers reconnect after the server upgrade, including their private runtime update and restart recovery.

bb account/cloud AI can become ready through existing Connect credentials and is preferred by automatic AI routing when available. Review service selections if you do not want titles, commit inputs or voice recordings sent to bb cloud; `bb ai off` persists that choice without signing the account out. See the [bb 0.45.0 release notes](https://github.com/get-bb/bb/blob/98f1c988777612723cc198e776ef407e2b6836ea/CHANGELOG.md).

## Updating bb within an image

bb 0.46.0 enables in-app updates by default, so the image's normal start commands do not need an update flag. Updates are available in Settings > Updates and through `bb updates app apply`. Applying an update stores the new version in the persistent home volume at `~/.bb/app-versions`; it does not replace the container or image. Back up state before updating. Installed app versions consume volume space, and bb does not automatically roll back a failed update. Use `bb-app start --bundled` to run the version baked into the image for recovery or to pin execution to that version. To disable in-app updates, pass `--no-in-app-updates` to `bb-app`. Check the baked and installed versions with `bb-image-info`.

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

Every flavor carries sudo, initially passwordless for `developer`. Standard container profiles (`full`, `slim`, and `worker`) block setuid elevation with `--security-opt no-new-privileges`; workers support `make hack`, not `make run`. You can deliberately permit container elevation with `SECURITY_OPTS=` on any container flavor. Direct engine launches without the flag permit sudo regardless of the tag. See [sudo and password setup](sudo.md) for `sudo bb-set-password`, recovery, and container recreation behavior.

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
