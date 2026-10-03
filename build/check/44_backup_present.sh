#!/bin/sh
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "bb-backup and its runtime dependencies are available in every flavor"
crun <<'SH'
set -eu
[ "$(readlink -f /usr/local/bin/bb-backup)" = /usr/local/share/bb/bb-backup ]
[ "$(stat -c '%U:%a' /usr/local/share/bb/bb-backup)" = root:755 ]
for command in zstd age sqlite3 rsync; do
	command -v "$command" >/dev/null || {
		echo "bb-backup dependency is missing: $command" >&2
		exit 1
	}
done
status=0
bb-backup >/tmp/bb-backup-usage 2>&1 || status=$?
[ "$status" = 2 ] || {
	echo "bare bb-backup exited $status, expected usage status 2" >&2
	exit 1
}
grep -q '^usage: bb-backup ' /tmp/bb-backup-usage
echo "bb-backup present, dependencies present, usage exit is 2"
SH
