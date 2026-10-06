# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: exedev

say "the exedev target carries the exe.dev adapter without enabling guest SSH"
crun <<'SH'
set -eu

[ "$(id -u)" = 0 ] || { echo "exedev must boot as root for systemd" >&2; exit 1; }
[ -x /usr/local/bin/init ]
grep -q '^exec /sbin/init' /usr/local/bin/init
[ -L /etc/systemd/system/multi-user.target.wants/bb.service ]
[ -f /etc/systemd/system/bb.service ]
grep -q 'User=developer' /etc/systemd/system/bb.service
grep -q 'ExecStart=.*--in-app-updates.*--server-port 3000' /etc/systemd/system/bb.service
[ "$(id -u developer)" = 1000 ]
[ -x /usr/sbin/sshd ]
[ ! -e /etc/systemd/system/multi-user.target.wants/ssh.service ]
[ ! -e /etc/systemd/system/multi-user.target.wants/ssh.socket ]
[ ! -e /etc/systemd/system/ssh-host-keys.service ]
[ ! -e /etc/ssh/ssh_host_rsa_key ]
[ ! -e /etc/ssh/ssh_host_ed25519_key ]

echo "exe.dev adapter present; guest SSH tooling installed but not enabled"
SH

exposed_ports="$($ENGINE image inspect "$img" --format '{{json .Config.ExposedPorts}}')"
[ "$exposed_ports" = null ] || {
	echo "exedev unexpectedly declares exposed ports: $exposed_ports" >&2
	exit 1
}
labels="$($ENGINE image inspect "$img" --format '{{json .Config.Labels}}')"
case "$labels" in
*'"exe.dev/login-user":"developer"'*) ;;
*)
	echo "exedev must declare developer as the exe.dev login user" >&2
	exit 1
	;;
esac
