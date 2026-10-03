# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: vm exedev worker-vm

say "VM flavors ship rootless Podman CLI, with no API socket"
crun <<'SH'
set -eu

for package in podman buildah aardvark-dns catatonit containers-storage uidmap \
	fuse-overlayfs slirp4netns dbus-user-session libpam-systemd; do
	status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
	[ "$status" = 'install ok installed' ] || {
		echo "required Podman package is not installed: $package" >&2
		exit 1
	}
done

case "$(podman --version)" in
*" version 5."*) ;;
*)
	echo "Podman must remain on Debian 13's supported 5.x line until rootless networking is revalidated" >&2
	exit 1
	;;
esac

[ "$(grep -c '^developer:100000:65536$' /etc/subuid)" = 1 ]
[ "$(grep -c '^developer:100000:65536$' /etc/subgid)" = 1 ]
grep -qx 'cgroup_manager = "systemd"' /etc/containers/containers.conf
grep -qx 'default_rootless_network_cmd = "slirp4netns"' /etc/containers/containers.conf
grep -qx 'z /dev/net/tun 0660 root developer -' /etc/tmpfiles.d/bb-podman-tun.conf
[ -f /var/lib/systemd/linger/developer ]
[ -f /etc/systemd/system/user@1000.service.d/mise.conf ]

for path in \
	/etc/systemd/system/sockets.target.wants/podman.socket \
	/etc/systemd/user/sockets.target.wants/podman.socket \
	/etc/systemd/system/sockets.target.wants/netavark-dhcp-proxy.socket \
	/etc/systemd/system/default.target.wants/netavark-dhcp-proxy.service; do
	[ ! -e "$path" ] || {
		echo "unexpected Podman-related socket or service is enabled: $path" >&2
		exit 1
	}
done

echo "Podman CLI configured rootless; no API or helper socket enabled"
SH
