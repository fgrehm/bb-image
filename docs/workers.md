# BB execution workers (prototype)

The `worker` and `worker-vm` build targets are **local prototypes, not published images**. They contain Node.js, npm, mise, and lazy coding-agent CLIs, but no baked BB server, host daemon, machine credentials, or enrollment hook. BB's [machine installer](https://github.com/get-bb/bb/blob/main/apps/server/src/assets/install-machine.sh) downloads the server's host-only build into its own private data directory after you explicitly enroll a machine. See [BB's multi-device guide](https://github.com/get-bb/bb/blob/main/docs/multiple-devices.md) for the enrollment flow and server connectivity requirements.

## Container

```bash
make ci FLAVOR=worker TAG=worker
podman run -d --name bb-worker --userns=keep-id --security-opt no-new-privileges \
  -v bb-worker-home:/home/developer bb:worker
podman exec -it bb-worker bash
```

Inside the container, run the **one-line installer generated for this machine** from Settings > Machines or `bb machine create --provider manual`. Do not bake that command or its bootstrap data into an image, Containerfile, script, or build argument. Add project bind mounts and network access when creating the container. Use a distinct home volume, never the server's `bb-home`, so credentials and machine identity survive a container recreate. The BB server must be reachable from the container; `127.0.0.1` inside the container is not the server host.

The container's default command only keeps it alive for manual setup. The installer falls back to a detached daemon when no systemd user manager is available. **Restart recovery for that daemon has not been validated:** after a container restart, do not assume the machine reconnected. No automatic enrollment or startup-time install is performed. The container needs an explicit, tested supervision policy before this is a supported worker flavor.

`make run FLAVOR=worker` is deliberately not supported: that target publishes the BB server port and mounts the server's home volume.

## VM

```bash
make ci FLAVOR=worker-vm TAG=worker-vm
```

Boot `bb:worker-vm` with smolvm's default VM-grade profile and a persistent disk, as described in [Running as a microVM](smolvm.md). Use a private Smolfile pointing at your **local** image or a local image archive; the repository's existing example points at a published BB server image and expects an API on port 38886. No `bb.service` is enabled in this worker target. The VM boots systemd and enables lingering for `developer` so its user manager can run an installer-created service after **manual** enrollment. Run the one-line installer as `developer`, not root, and verify `systemctl --user` is available and the installed `bb-host-daemon-*.service` is active. If the user manager is unavailable, the installer falls back to a detached daemon instead.

A local smolvm boot and stop/start test confirmed the `developer` user manager and user bus start without enrollment, and a transient non-login user service resolves `/opt/mise/shims/node`. Wait for `systemctl is-active user@1000.service` before using `systemctl --user` immediately after boot. The installer-generated BB service, enrollment, and daemon recovery after restart remain untested. Do not publish these targets or rely on them for unattended workers until those flows pass.
