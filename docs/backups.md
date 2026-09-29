# Backups

`bb-backup` ships in `full`, `full-sudo`, `vm`, `vm-sudo`, and `exedev`, not slim or worker flavors. The underlying age and SQLite tools are available in every flavor.

`/usr/local/share/bb/bb-backup` has four subcommands and no default: `backup` (the recovery archive), `state` (the discovered bb profile), `traces` (the additive mirror), and `verify`. A bare `bb-backup` prints usage. It does not schedule anything. Container deployments should call it from a host systemd user timer, a Quadlet, or a compose sidecar cron. The `vm` flavors have systemd and a managed bb service, but deliberately ship no backup timer; a derived VM can add one when its backup destination and retention policy are known.

## Recovery archive

`backup` preserves explicit source selection for deployments with custom layouts. For this image's conventional bb-owned state, `state` discovers a bounded profile and uses the same snapshot, verification, retention, and restore machinery:

```bash
bb-backup state --output /backups --keep 7
bb-backup state --output /backups --include-secrets --age-recipient age1... --include ~/.bb/plugin-host-artifacts
```

Generate a key pair with `age-keygen`; keep the private identity outside the image and store its printed `age1...` recipient somewhere durable for backup jobs. To restore, decrypt with `age -d -i IDENTITY backup.tar.zst.age > backup.tar.zst`, then verify and extract the resulting archive as described below.

### State scope

The profile includes `~/.bb/bb.db`, bb logs, pi-bridge sessions, pi-extras sessions, thread storage, Pi agent sessions, and per-plugin state. It discovers plugin SQLite files (`*.db`, `*.sqlite`, and `*.sqlite3`) and snapshots them with SQLite's online backup API. Other plugin data files and directories such as `logs/`, `host-data/`, and `bridge-data/` are included.

Automatic selection excludes plugin `secrets/` and managed code/install trees: top-level `git/` and `npm/` roots, `toolchain-*`, `node_modules`, and directories named `runtime`, `cache`, `dist`, `build`, `src`, `source`, `install`, or `installs`. Database discovery prunes those trees too. State archives exclude raw SQLite `-wal`/`-shm` sidecars. The profile does not sweep the rest of `$HOME`.

### Caller inclusions and secrets

Repeat `--include PATH` to add existing files or directories. State exclusion patterns still apply to these paths, so an include does not override a matching exclusion. SQLite discovery does not scan arbitrary caller includes: name additional live databases with `--sqlite PATH` to snapshot them consistently. Explicit `--sqlite` requests are appended as snapshots independently of the state exclusions; do not use them to name secrets or managed databases you intend to exclude.

`--include-secrets` opts plugin secrets into automatic selection. It does not require encryption, so request `--age-recipient` when these credentials must not be published as plaintext.

Source, include, and SQLite path lists do not support whitespace, even when command-line arguments are quoted. This limitation also affects discovered paths and trace sources. Keep output and temporary staging outside the selected source trees to avoid archiving backup artifacts. Use explicit `backup` mode when the state profile's exclusions do not fit your layout.

### Encryption and output

`--output DIR` selects the destination. Without encryption, archives are plaintext `.tar.zst` files. `--age-recipient RECIPIENT` encrypts the verified archive and publishes only `backup-<timestamp>.tar.zst.age` to that destination. Plaintext exists temporarily in a mode-0700 staging directory under `${TMPDIR:-/tmp}`. Use private local staging, not a synced destination. Cleanup removes staging files on normal exit; it is not secure erasure and cannot survive SIGKILL or a machine crash. Private decryption identities are supplied by the operator, never baked into the image.

`--keep N` prunes matching plaintext and encrypted archives together in the output directory; its default, zero, prunes nothing. Use separate destinations for independent retention policies.

### Explicit backup and restore

```bash
bb-backup backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

That writes `/backups/backup-<timestamp>.tar.zst`, snapshotting the live bb database (only for the `--sqlite` paths you name; the sources are copied as-is otherwise) so the archive is not a mid-write mix of pages, keeping the 7 newest archives, and pruning the rest. Every archive is verified before it is named: the zstd stream is tested (`zstd -t`) and the tar payload is listed end to end (`tar -tf`), so a truncated or corrupt archive exits nonzero and never lands under the canonical name. `bb-backup verify FILE` re-runs that check for restore flows. For an age-encrypted archive, decrypt it to a private temporary `.tar.zst` first, then pass that file to `verify`; the image does not carry private identities.

Restore is plain tar, but archive entries are relative to the filesystem root (`home/developer/...`), not the home directory. Extract into a staging directory, then copy its `home/developer/` contents into a fresh home volume while bb is stopped; recreate the container with that volume. The sqlite snapshot is stored at the same path as the original database and replaces its archived copy on extraction.

To run it from the host, bind the output directory and the state you are archiving:

```bash
podman run --rm -v bb-home:/home/developer:ro -v /var/backups/bb:/backups \
    ghcr.io/fgrehm/bb /usr/local/share/bb/bb-backup \
    backup --output /backups --sqlite /home/developer/.bb/bb.db --keep 7 /home/developer
```

The read-only mount keeps bb free to serve while the archive runs; the sqlite snapshot covers the one file that would otherwise be mid-write. For a scheduled setup, wrap that command in a systemd user timer with `Persistent=true`, so missed runs are caught up after a reboot.

## Trace archival

`bb-backup traces` mirrors agent session traces and logs into a directory with rsync, additively and independently of bb: pi sessions (`~/.pi/agent/sessions`), bb logs (`~/.bb/logs`), the pi bridge (`~/.bb/pi-bridge-sessions`), pi-extras title/commit traces (`~/.bb/pi-extras-sessions`), and claude and codex state (`~/.claude`, `~/.codex`) are included by default when they exist. Locations a deployment always wants can be baked into the environment with `BB_BACKUP_TRACES_INCLUDES` (colon-separated, like `PATH`, missing entries skipped), so a compose file or timer unit carries the convention without flags; `--include PATH` adds paths on top and must exist. It never prunes and never deletes: each run selects files with modification times newer than the `.traces-last` marker in the output directory, and a file the source later removes stays in the mirror if it was already copied. Run it before traces are deleted or rotated away; files removed between runs, or introduced with modification times older than the marker, are not captured.

Two layouts, chosen with a flag. The default preserves full source paths in the mirror (`/traces/home/developer/.bb/logs/server.log`). `--flatten` merges every source into the target instead, preserving the structure below each include, like a manual `rsync -av src/* dest/`. That is what a synced remote usually wants, one directory per tool rather than one per machine or container:

```bash
bb-backup traces --output /mnt/traces/this-host/pi --flatten \
    --include ~/.pi/agent/sessions \
    --include ~/.local/share/pairoot/home/.pi/agent/sessions
bb-backup traces --output /mnt/traces/this-host/bb --flatten \
    --include ~/.bb/pi-bridge-sessions \
    --include ~/.bb/pi-extras-sessions \
    --include ~/.local/share/pairoot/home/.bb/pi-bridge-sessions
bb-backup traces --output /mnt/traces/work/claude --flatten \
    --include ~/.claude/projects \
    --include ~/Work/devpod-data/claude/projects \
    --include ~/Work/smol-data/claude/projects
```

Flatten mode merges by relative path, so two sources holding the same relative path overwrite each other (last write wins, nothing removed). In practice that is rare: session traces are UUID- and thread-id-named, so distinct sources almost never hold the same name. Traces are plain files in the mirror, not an archive: read them directly, or rsync the mirror wherever you keep history. rsync's exit status is the integrity check, and a failed run leaves the marker unmoved, so the next run picks up the same files. Run it from a timer as often as you like; empty runs write nothing.
