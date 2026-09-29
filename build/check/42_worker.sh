# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: worker worker-vm

say "worker has Node and agent shims, but no baked BB or enrollment"
node_arg="$(sed -n 's/^ARG BB_NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
slim_node="$(sed -n 's/^node = "\(.*\)"$/\1/p' "$root/container/mise-slim.toml")"
[ "$node_arg" = "$slim_node" ] || {
	echo "node mismatch: Containerfile says '$node_arg', mise-slim.toml says '$slim_node'" >&2
	exit 1
}
crun --env BB_NODE_VERSION="$node_arg" <<'SH'
set -eu
[ "$(id -u)" = "$( [ "$FLAVOR" = worker ] && id -u developer || echo 0 )" ] || {
	echo "unexpected worker image user" >&2
	exit 1
}
[ "$(node --version)" = "v$BB_NODE_VERSION" ]
command -v npm >/dev/null
for c in claude codex pi opencode pnpm playwright; do command -v "$c" >/dev/null; done
playwright_arg="$(sed -n 's/^ARG PLAYWRIGHT_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
[ "$(playwright --version 2>/dev/null | sed -n 's/^Version //p')" = "$playwright_arg" ] || {
	echo "worker Playwright version does not match foundation pin" >&2
	exit 1
}
[ -d /opt/ms-playwright ] || { echo "worker Chromium browser is missing" >&2; exit 1; }
for c in bb bb-app sudo; do
	if command -v "$c" >/dev/null 2>&1; then
		echo "worker unexpectedly has $c" >&2
		exit 1
	fi
done
for path in /home/developer/.bb/auth.json /home/developer/.bb-machines \
	/etc/systemd/system/bb.service /usr/local/share/bb/bb-backup \
	/home/developer/entrypoint.sh; do
	[ ! -e "$path" ] || { echo "worker unexpectedly carries $path" >&2; exit 1; }
done
[ -w /opt/mise ] || { echo "mise is not writable by the image user" >&2; exit 1; }
if [ "$FLAVOR" = worker-vm ]; then
	[ "$(readlink -f /sbin/init)" = /usr/lib/systemd/systemd ]
	[ -f /var/lib/systemd/linger/developer ]
	[ ! -s /etc/machine-id ]
	[ ! -e /var/lib/dbus/machine-id ]
	[ -d /etc/systemd/system/user@1000.service.d ]
	[ -f /etc/systemd/system/user@1000.service.d/mise.conf ]
	[ -f /lib/x86_64-linux-gnu/security/pam_systemd.so ]
else
	[ ! -e /sbin/init ] || { echo "container worker unexpectedly carries systemd" >&2; exit 1; }
fi
echo "worker runtime and Playwright present, no server or enrollment baked in"
SH

case "$FLAVOR" in
worker) expected='["sleep","infinity"]' ;;
worker-vm) expected='["/sbin/init"]' ;;
esac
cmd="$("$ENGINE" image inspect "$img" --format '{{json .Config.Cmd}}')"
[ "$cmd" = "$expected" ] || {
	echo "$FLAVOR has command $cmd, expected $expected" >&2
	exit 1
}
