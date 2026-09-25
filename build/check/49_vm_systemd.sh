# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-flavors: vm vm-sudo

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
printf '%s\n' "$unit" | grep -qx 'ExecStart=/opt/mise/shims/bb-app --server-bind-host 0.0.0.0 --server-port 38886'
printf '%s\n' "$unit" | grep -qx 'WantedBy=multi-user.target'

[ ! -s /etc/machine-id ] || {
	echo "the image bakes a machine identity; each VM must initialize its own" >&2
	exit 1
}
[ ! -e /var/lib/dbus/machine-id ] || {
	echo "the image bakes a D-Bus machine identity" >&2
	exit 1
}

case "$FLAVOR" in
vm)
	if command -v sudo >/dev/null 2>&1; then
		echo "the standard VM flavor unexpectedly contains sudo" >&2
		exit 1
	fi
	;;
vm-sudo)
	[ "$(su -s /bin/sh developer -c 'sudo -n id -u')" = 0 ] || {
		echo "developer cannot use passwordless sudo inside the VM" >&2
		exit 1
	}
	[ "$(stat -c %a /etc/sudoers.d/developer)" = 440 ] || {
		echo "sudoers rule is not mode 0440" >&2
		exit 1
	}
	;;
esac

echo "systemd image contract is present for $FLAVOR"
SH
