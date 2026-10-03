#!/bin/sh
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: worker worker-vm

say "bb-backup handles a worker without bb state and mirrors a trace"
crun <<'SH'
set -eu
bb-backup state --output /tmp/bb-backup-empty
[ ! -e /tmp/bb-backup-empty ] || {
	echo "empty state backup unexpectedly created an output directory" >&2
	exit 1
}
mkdir -p /tmp/bb-backup-session
printf '%s\n' worker-session > /tmp/bb-backup-session/session.txt
bb-backup traces --output /tmp/bb-backup-traces --include /tmp/bb-backup-session
grep -qx worker-session /tmp/bb-backup-traces/tmp/bb-backup-session/session.txt
echo "empty state is a successful no-op; worker trace mirrored"
SH
