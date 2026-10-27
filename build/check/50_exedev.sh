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
grep -qx 'User=developer' /etc/systemd/system/bb.service
grep -qx 'ExecStart=/opt/mise/shims/bb-app' /etc/systemd/system/bb.service
if grep -qE -- '--server-(bind-host|port)' /etc/systemd/system/bb.service; then
	echo "exedev hardcodes the listener instead of sharing the VM unit" >&2
	exit 1
fi
# exedev inherits the shared unit from vm and replaces only the image default.
# Port 3000 is the exe.dev proxy's first forwarded port; if this file were
# missing, bb would silently fall back to the VM default on 38886.
grep -qx 'BB_SERVER_BIND_HOST=127.0.0.1' /etc/bb/listener.env
grep -qx 'BB_SERVER_PORT=3000' /etc/bb/listener.env
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
