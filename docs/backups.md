# Backups

`/usr/local/share/bb/bb-backup` has three subcommands and no default: `backup` (the recovery archive), `traces` (the additive mirror), and `verify`. A bare `bb-backup` prints usage. It does not schedule anything: the image is rootless and ships no boot-time service, so the timer lives wherever the container is run from (a host systemd user timer, a Quadlet, or a compose sidecar cron) and calls this script.

## Recovery archive

```bash
bb-backup backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

That writes `/backups/backup-<timestamp>.tar.zst`, snapshotting the live bb database (only for the `--sqlite` paths you name; the sources are copied as-is otherwise) so the archive is not a mid-write mix of pages, keeping the 7 newest archives, and pruning the rest. Every archive is verified before it is named: the zstd stream is tested (`zstd -t`) and the tar payload is listed end to end (`tar -tf`), so a truncated or corrupt archive exits nonzero and never lands under the canonical name. `bb-backup verify FILE` re-runs that check for restore flows.

Restore is plain tar: unpack the archive over a fresh home, then recreate the container with that volume. The sqlite snapshot unpacks to its real path and replaces the live database's copy.

To run it from the host, bind the output directory and the state you are archiving:

```bash
podman run --rm -v bb-home:/home/developer:ro -v /var/backups/bb:/backups \
    ghcr.io/fgrehm/bb /usr/local/share/bb/bb-backup \
    backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

The read-only mount keeps bb free to serve while the archive runs; the sqlite snapshot covers the one file that would otherwise be mid-write. For a scheduled setup, wrap that command in a systemd user timer with `Persistent=true`, so missed runs are caught up after a reboot.

## Trace archival

`bb-backup traces` mirrors agent session traces and logs into a directory with rsync, additively and independently of bb: pi sessions (`~/.pi/agent/sessions`), bb logs (`~/.bb/logs`), the pi bridge (`~/.bb/pi-bridge-sessions`), and claude and codex state (`~/.claude`, `~/.codex`) are included by default when they exist. Locations a deployment always wants can be baked into the environment with `BB_BACKUP_TRACES_INCLUDES` (colon-separated, like `PATH`, missing entries skipped), so a compose file or timer unit carries the convention without flags; `--include PATH` adds paths on top and must exist. It never prunes and never deletes: each run copies only the files modified since the previous run (tracked by a `.traces-last` marker in the output directory, with nanosecond precision so nothing at the boundary is missed), and a file the source later removes stays in the mirror. The directory accumulates every trace the CLIs ever wrote.

Two layouts, chosen with a flag. The default preserves full source paths in the mirror (`/traces/home/developer/.bb/logs/server.log`). `--flatten` merges every source into the target instead, structure below each include preserved — the shape a manual `rsync -av src/* dest/` produces. That is what a synced remote usually wants, one directory per tool rather than one per machine or container:

```bash
bb-backup traces --output /mnt/traces/this-host/pi --flatten \
    --include ~/.pi/agent/sessions \
    --include ~/.local/share/pairoot/home/.pi/agent/sessions
bb-backup traces --output /mnt/traces/this-host/bb --flatten \
    --include ~/.bb/pi-bridge-sessions \
    --include ~/.local/share/pairoot/home/.bb/pi-bridge-sessions
bb-backup traces --output /mnt/traces/work/claude --flatten \
    --include ~/.claude/projects \
    --include ~/Work/devpod-data/claude/projects \
    --include ~/Work/smol-data/claude/projects
```

Flatten mode merges by relative path, so two sources holding the same relative path overwrite each other (last write wins, nothing removed). In practice that is rare: session traces are UUID- and thread-id-named, so distinct sources almost never hold the same name. Traces are plain files in the mirror, not an archive: read them directly, or rsync the mirror wherever you keep history. rsync's exit status is the integrity check, and a failed run leaves the marker unmoved, so the next run picks up the same files. Run it from a timer as often as you like; empty runs write nothing.
