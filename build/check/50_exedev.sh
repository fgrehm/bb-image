# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-flavors: exedev

say "the exedev target carries the exe.dev adapter"
crun <<'SH'
set -eu

[ "$(id -u)" = 0 ] || { echo "exedev must boot as root for systemd" >&2; exit 1; }
[ -x /usr/local/bin/init ]
grep -q '^exec /sbin/init' /usr/local/bin/init
[ -L /etc/systemd/system/multi-user.target.wants/ssh-host-keys.service ]
[ -L /etc/systemd/system/multi-user.target.wants/ssh.service ]
[ -L /etc/systemd/system/multi-user.target.wants/bb.service ]
[ -f /etc/systemd/system/bb.service ]
grep -q '^Before=ssh.service$' /etc/systemd/system/ssh-host-keys.service
grep -q '^ExecStart=/usr/bin/ssh-keygen -A$' /etc/systemd/system/ssh-host-keys.service
grep -q 'User=developer' /etc/systemd/system/bb.service
grep -q 'ExecStart=.*--server-port 3000' /etc/systemd/system/bb.service
[ "$(id -u developer)" = 1000 ]
[ ! -e /etc/ssh/ssh_host_rsa_key ]
[ ! -e /etc/ssh/ssh_host_ed25519_key ]

echo "exe.dev adapter is present"
SH
