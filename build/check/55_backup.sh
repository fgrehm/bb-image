# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# The backup script is baked in full and inherited unchanged by the rest of the
# full lineage, so the round trip runs on full alone. The script is one layer,
# identical in every flavor that carries it.
# check-flavors: full

# The baked backup script: a backup with a live sqlite snapshot must produce a
# verified archive, retention must prune, a corrupted archive must fail the
# verify, and the snapshot inside the archive must unpack as a usable database.
say "bb-backup round trip inside the image"
crun <<'SH'
set -eu
# The script is reached through the PATH symlink, so the symlink itself, its
# exec bit, and what it points at are all part of the round trip.
command -v zstd >/dev/null
command -v age >/dev/null
command -v age-keygen >/dev/null
command -v sqlite3 >/dev/null
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

echo "state: discover bb and plugin state with consistent SQLite snapshots"
mkdir -p /tmp/state/.bb/plugins/example/{logs,secrets,node_modules} /tmp/state/.bb/plugins/{git,npm} /tmp/state/.pi/agent/sessions /tmp/state/.bb/pi-extras-sessions
sqlite3 /tmp/state/.bb/bb.db 'create table core(x); insert into core values (7);'
sqlite3 /tmp/state/.bb/plugins/example/data.db 'create table plugin(x); insert into plugin values (9);'
sqlite3 /tmp/state/.bb/plugins/git/managed.db 'create table managed(x); insert into managed values (1);'
sqlite3 /tmp/state/.bb/plugins/npm/managed.sqlite 'create table managed(x); insert into managed values (1);'
mkdir -p /tmp/state/.bb/plugins/toolchain-test /tmp/state/.bb/plugins/example/toolchain-nested
sqlite3 /tmp/state/.bb/plugins/toolchain-test/managed.db 'create table managed(x);'
sqlite3 /tmp/state/.bb/plugins/example/toolchain-nested/managed.sqlite 'create table managed(x);'
printf 'managed git source\n' > /tmp/state/.bb/plugins/git/source.js
printf 'managed npm source\n' > /tmp/state/.bb/plugins/npm/package.json
printf 'runtime data\n' > /tmp/state/.bb/plugins/example/logs/plugin.log
printf 'credential\n' > /tmp/state/.bb/plugins/example/secrets/apiKey
printf 'managed source\n' > /tmp/state/.bb/plugins/example/node_modules/source.js
printf 'thread trace\n' > /tmp/state/.pi/agent/sessions/t1.jsonl
printf 'pi-extras trace\n' > /tmp/state/.bb/pi-extras-sessions/pi-extras-title-test.jsonl
mkdir /tmp/state-out
HOME=/tmp/state "$bb" state --output /tmp/state-out
state_arch=$(ls /tmp/state-out/*.tar.zst)
"$bb" verify "$state_arch"
mkdir /tmp/state-restore
tar -C /tmp/state-restore -xf "$state_arch"
[ "$(sqlite3 /tmp/state-restore/tmp/state/.bb/bb.db 'select x from core')" = 7 ]
[ "$(sqlite3 /tmp/state-restore/tmp/state/.bb/plugins/example/data.db 'select x from plugin')" = 9 ]
[ "$(cat /tmp/state-restore/tmp/state/.bb/plugins/example/logs/plugin.log)" = 'runtime data' ]
[ -e /tmp/state-restore/tmp/state/.pi/agent/sessions/t1.jsonl ]
[ -e /tmp/state-restore/tmp/state/.bb/pi-extras-sessions/pi-extras-title-test.jsonl ]
if tar -tf "$state_arch" | grep -E '/secrets/|/\.bb/plugins/(git|npm)/|/toolchain-[^/]+/|/node_modules/|-(wal|shm)$'; then
	echo "state profile included plugin secrets, managed installs, or raw SQLite sidecars" >&2
	exit 1
fi

# Explicit inclusions and secret opt-in are safe when encryption is requested:
# only the ciphertext reaches the output directory, and decrypting it restores
# the verified archive layout.
mkdir -p /tmp/state-extra /tmp/state-encrypted-out /tmp/state-stage
printf 'old ciphertext\n' > /tmp/state-encrypted-out/backup-20000101-000000.tar.zst.age
printf 'unrelated file\n' > /tmp/state-encrypted-out/keep.txt
printf 'caller data\n' > /tmp/state-extra/custom.txt
sqlite3 /tmp/state-extra/custom.sqlite 'create table extra(x); insert into extra values (17);'
age-keygen -o /tmp/state-identity.txt 2>/tmp/state-keygen.log
state_recipient=$(sed -n 's/^# public key: //p' /tmp/state-identity.txt)
[ "$state_recipient" != '' ]
HOME=/tmp/state TMPDIR=/tmp/state-stage "$bb" state --output /tmp/state-encrypted-out --include /tmp/state-extra --sqlite /tmp/state-extra/custom.sqlite --include-secrets --age-recipient "$state_recipient" --keep 1
state_cipher=$(ls /tmp/state-encrypted-out/*.tar.zst.age)
[ ! -e /tmp/state-encrypted-out/backup-20000101-000000.tar.zst.age ]
[ -e /tmp/state-encrypted-out/keep.txt ]
[ "$(find /tmp/state-encrypted-out -maxdepth 1 -type f -name '*.tar.zst*' | wc -l)" = 1 ]
[ -z "$(find /tmp/state-stage -mindepth 1 -print -quit)" ]
age --decrypt -i /tmp/state-identity.txt --output /tmp/state-decrypted.tar.zst "$state_cipher"
"$bb" verify /tmp/state-decrypted.tar.zst
mkdir /tmp/state-decrypted
tar -C /tmp/state-decrypted -xf /tmp/state-decrypted.tar.zst
[ -e /tmp/state-decrypted/tmp/state/.bb/plugins/example/secrets/apiKey ]
if tar -tf /tmp/state-decrypted.tar.zst | grep -E '/toolchain-[^/]+/'; then
	echo "secret opt-in included managed toolchain databases" >&2
	exit 1
fi
[ "$(cat /tmp/state-decrypted/tmp/state-extra/custom.txt)" = 'caller data' ]
[ "$(sqlite3 /tmp/state-decrypted/tmp/state-extra/custom.sqlite 'select x from extra')" = 17 ]

echo "traces: additive rsync mirror"
# A bare invocation assumes no strategy, by design.
if "$bb" >/dev/null 2>&1; then
	echo "bare bb-backup invocation must fail" >&2
	exit 1
fi
mkdir -p /tmp/src/.claude/projects /tmp/src/.codex/sessions /tmp/src/.bb/pi-extras-sessions
printf 'claude-1\n' > /tmp/src/.claude/projects/c1.jsonl
printf 'codex-1\n' > /tmp/src/.codex/sessions/x1.jsonl
printf 'title trace\n' > /tmp/src/.bb/pi-extras-sessions/pi-extras-title-test.jsonl
HOME=/tmp/src "$bb" traces --output /tmp/out
[ "$(cat /tmp/out/tmp/src/.pi/agent/sessions/s1.jsonl)" = session-1 ]
[ "$(cat /tmp/out/tmp/src/.claude/projects/c1.jsonl)" = claude-1 ]
[ "$(cat /tmp/out/tmp/src/.codex/sessions/x1.jsonl)" = codex-1 ]
[ "$(cat /tmp/out/tmp/src/.bb/pi-extras-sessions/pi-extras-title-test.jsonl)" = 'title trace' ]
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
