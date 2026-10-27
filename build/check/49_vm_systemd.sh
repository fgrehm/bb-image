# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-flavors: vm

say "the VM target carries an enabled systemd-managed bb service"
crun <<'SH'
set -eu

[ "$(id -u)" = 0 ] || {
	echo "the vm flavor must boot its init system as root" >&2
	exit 1
}
dpkg-query -W -f='${Status}\n' libnss-myhostname | grep -qx 'install ok installed' || {
	echo "libnss-myhostname is not installed" >&2
	exit 1
}
grep -Eq '^hosts:[[:space:]]+files[[:space:]]+myhostname[[:space:]]+dns$' /etc/nsswitch.conf || {
	echo "the guest hostname is not routed through nss-myhostname" >&2
	exit 1
}
[ "$(readlink -f /sbin/init)" = /usr/lib/systemd/systemd ] || {
	echo "/sbin/init does not resolve to systemd" >&2
	exit 1
}
enabled=/etc/systemd/system/multi-user.target.wants/bb.service
[ -L "$enabled" ] && [ "$(readlink -f "$enabled")" = /etc/systemd/system/bb.service ] || {
	echo "bb.service is not enabled for multi-user.target" >&2
	exit 1
}
systemd-analyze verify /etc/systemd/system/bb.service

unit="$(cat /etc/systemd/system/bb.service)"
printf '%s\n' "$unit" | grep -qx 'User=developer'
printf '%s\n' "$unit" | grep -qx 'WorkingDirectory=/home/developer'
printf '%s\n' "$unit" | grep -qx 'ExecStartPre=/usr/local/share/bb/hydrate-home.sh install'
printf '%s\n' "$unit" | grep -qx 'ExecStart=/opt/mise/shims/bb-app'
printf '%s\n' "$unit" | grep -qx 'WantedBy=multi-user.target'

# The listener is bb's own environment contract, not a unit flag: the image
# default is read first and the operator file after it, so a later variable wins.
envfiles="$(printf '%s\n' "$unit" | grep '^EnvironmentFile=')"
expected_envfiles='EnvironmentFile=-/etc/bb/listener.env
EnvironmentFile=-/etc/default/bb'
[ "$envfiles" = "$expected_envfiles" ] || {
	echo "the unit's environment files are not the expected pair in order: $envfiles" >&2
	exit 1
}
if printf '%s\n' "$unit" | grep -qE -- '--server-(bind-host|port)'; then
	echo "the unit still hardcodes the listener instead of reading the environment" >&2
	exit 1
fi

[ "$(stat -c '%U:%a' /etc/bb/listener.env)" = root:644 ]
grep -qx 'BB_SERVER_BIND_HOST=127.0.0.1' /etc/bb/listener.env
grep -qx 'BB_SERVER_PORT=38886' /etc/bb/listener.env
if grep -q 'BB_SERVER_PORT=' /etc/default/bb 2>/dev/null; then
	echo "the image ships an operator override in /etc/default/bb" >&2
	exit 1
fi

[ ! -s /etc/machine-id ] || {
	echo "the image bakes a machine identity; each VM must initialize its own" >&2
	exit 1
}
[ ! -e /var/lib/dbus/machine-id ] || {
	echo "the image bakes a D-Bus machine identity" >&2
	exit 1
}

# Shared bootstrap sudo and elevation refusal are covered by 48_sudo.

echo "systemd image contract is present for $FLAVOR"
SH
