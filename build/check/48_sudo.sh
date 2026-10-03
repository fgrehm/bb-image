# Partials sourced by build/check.sh via build/check/lib.sh.
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "every flavor carries bootstrap sudo and the human setup helper"
crun --user developer <<'SH'
set -eu
[ "$(id -u)" = 1000 ]
[ "$(sudo -n id -u)" = 0 ]
sudo -n visudo -c
for path in /etc/sudoers.d/developer /etc/sudoers.d/zz-bb-bootstrap; do
	[ "$(stat -c '%U:%a' "$path")" = root:440 ]
done
sudo -n grep -qx 'developer ALL=(ALL) PASSWD: ALL' /etc/sudoers.d/developer
sudo -n grep -qx 'developer ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/zz-bb-bootstrap
[ "$(stat -c '%U:%a' /usr/local/sbin/bb-set-password)" = root:755 ]
command -v flock >/dev/null
command -v runuser >/dev/null
if bb-set-password >/dev/null 2>&1; then
	echo "unprivileged setup unexpectedly succeeded" >&2
	exit 1
fi
SH

say "no-new-privileges blocks bootstrap elevation"
crun --user developer --security-opt no-new-privileges <<'SH'
set -eu
grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status
if sudo -n true >/dev/null 2>&1; then
	echo "sudo worked despite no-new-privileges" >&2
	exit 1
fi
SH
