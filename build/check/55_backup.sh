# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full full-sudo exedev

# The baked backup script: a backup with a live sqlite snapshot must produce a
# verified archive, retention must prune, a corrupted archive must fail the
# verify, and the snapshot inside the archive must unpack as a usable database.
say "bb-backup round trip inside the image"
crun <<'SH'
set -eu
# The script is reached through the PATH symlink, so the symlink itself, its
# exec bit, and what it points at are all part of the round trip.
command -v zstd >/dev/null
command -v rsync >/dev/null
[ -x /usr/local/bin/bb-backup ]
[ "$(readlink -f /usr/local/bin/bb-backup)" = /usr/local/share/bb/bb-backup ]
bb=/usr/local/bin/bb-backup
mkdir -p /tmp/src/.bb /tmp/src/.pi/agent/sessions /tmp/out
printf 'payload\n' > /tmp/src/data.txt
printf 'session-1\n' > /tmp/src/.pi/agent/sessions/s1.jsonl
sqlite3 /tmp/src/.bb/bb.db 'create table t(x); insert into t values (41), (42);'

# Backup, with the live db snapshotted and the output pruned to one archive.
"$bb" backup --output /tmp/out --sqlite /tmp/src/.bb/bb.db --keep 1 /tmp/src
arch_before="$(ls /tmp/out/*.tar.zst)"
# The canonical name always passes verify, checked before retention can
# prune it and the name has second resolution; space the runs out so the
# second one gets its own name instead of overwriting the first.
"$bb" verify "$arch_before"
sleep 1
"$bb" backup --output /tmp/out --keep 1 /tmp/src
[ "$(ls /tmp/out/*.tar.zst | wc -l)" = 1 ]
arch="$(ls /tmp/out/*.tar.zst)"

"$bb" verify "$arch"

# A truncated archive is refused, in the backup flow's own check.
cp -- "$arch" /tmp/out/keepme.zst
truncate -s 200 -- "$arch"
if "$bb" verify "$arch" >/dev/null 2>&1; then
	echo "verify accepted a truncated archive" >&2
	exit 1
fi
mv /tmp/out/keepme.zst "$arch"

# The snapshot unpacks to its real path and is a working database.
mkdir /tmp/restore
tar -C /tmp/restore -xf "$arch"
[ "$(cat /tmp/restore/tmp/src/data.txt)" = payload ]
[ "$(sqlite3 /tmp/restore/tmp/src/.bb/bb.db 'select count(*) from t')" = 2 ]

echo "traces: additive rsync mirror"
# A bare invocation assumes no strategy, by design.
if "$bb" >/dev/null 2>&1; then
	echo "bare bb-backup invocation must fail" >&2
	exit 1
fi
mkdir -p /tmp/src/.claude/projects /tmp/src/.codex/sessions
printf 'claude-1\n' > /tmp/src/.claude/projects/c1.jsonl
printf 'codex-1\n' > /tmp/src/.codex/sessions/x1.jsonl
HOME=/tmp/src "$bb" traces --output /tmp/out
[ "$(cat /tmp/out/tmp/src/.pi/agent/sessions/s1.jsonl)" = session-1 ]
[ "$(cat /tmp/out/tmp/src/.claude/projects/c1.jsonl)" = claude-1 ]
[ "$(cat /tmp/out/tmp/src/.codex/sessions/x1.jsonl)" = codex-1 ]
HOME=/tmp/src "$bb" traces --output /tmp/out | grep 'nothing new'
sleep 1
printf 'session-2\n' > /tmp/src/.pi/agent/sessions/s2.jsonl
mkdir -p /tmp/src/.bb/logs
printf 'more\n' > /tmp/src/.bb/logs/server.log
HOME=/tmp/src "$bb" traces --output /tmp/out
[ "$(cat /tmp/out/tmp/src/.pi/agent/sessions/s2.jsonl)" = session-2 ]
[ "$(cat /tmp/out/tmp/src/.bb/logs/server.log)" = more ]
[ ! -e /tmp/out/tmp/src/.bb/bb.db ]

# Flatten merges every source into the target, entries relative to each
# include: the shape a manual `rsync -av src/* dest/` produces, one
# directory per tool for a synced remote.
HOME=/tmp/src "$bb" traces --output /tmp/out-flat --flatten
[ "$(cat /tmp/out-flat/s1.jsonl)" = session-1 ]
[ "$(cat /tmp/out-flat/s2.jsonl)" = session-2 ]
[ "$(cat /tmp/out-flat/server.log)" = more ]
[ "$(cat /tmp/out-flat/projects/c1.jsonl)" = claude-1 ]
[ "$(cat /tmp/out-flat/sessions/x1.jsonl)" = codex-1 ]
[ ! -e /tmp/out-flat/tmp ]

# Additive, not a mirror with --delete: a source file removed after it was
# copied stays in the output.
rm /tmp/src/.pi/agent/sessions/s1.jsonl
sleep 1
HOME=/tmp/src "$bb" traces --output /tmp/out
[ -e /tmp/out/tmp/src/.pi/agent/sessions/s1.jsonl ]

echo "bb-backup ok"
SH
