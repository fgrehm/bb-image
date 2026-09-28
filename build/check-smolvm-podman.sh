#!/bin/sh
# Host-only rootless Podman test inside a VM-grade smolvm guest. This requires
# KVM/libkrun and intentionally does not run under make check's container.
set -eu

SMOLVM="${SMOLVM:-smolvm}"
ENGINE="${ENGINE:-podman}"
IMAGE="${IMAGE:-bb}"
FLAVOR="${FLAVOR:-vm}"
TAG="${TAG:-$FLAVOR}"
case "$FLAVOR" in
vm | vm-sudo | exedev | worker-vm) ;;
*)
	echo "unsupported Podman VM flavor: $FLAVOR" >&2
	exit 1
	;;
esac

name="bb-podman-check-$FLAVOR-$$"
tmp="${TMPDIR:-/tmp}/bb-podman-check-$FLAVOR-$$"
archive="$tmp/image.tar"
created=0
running=0

cleanup() {
	if [ "$created" = 1 ]; then
		[ "$running" = 0 ] || "$SMOLVM" machine stop --name "$name" >/dev/null 2>&1 || true
		"$SMOLVM" machine delete --name "$name" -f >/dev/null 2>&1 || true
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$tmp"

command -v "$SMOLVM" >/dev/null 2>&1 || {
	echo "smolvm is required on the host" >&2
	exit 1
}
command -v "$ENGINE" >/dev/null 2>&1 || {
	echo "$ENGINE is required to export the image" >&2
	exit 1
}

marker="$($ENGINE image inspect "$IMAGE:$TAG" --format '{{ index .Config.Labels "sh.bb.flavor" }}')"
[ "$marker" = "$FLAVOR" ] || {
	echo "$IMAGE:$TAG is marked '$marker', expected $FLAVOR" >&2
	exit 1
}

"$ENGINE" save "$IMAGE:$TAG" -o "$archive"
"$SMOLVM" machine create --name "$name" --image "$archive" --net
created=1
timeout 120 "$SMOLVM" machine start --name "$name"
running=1

user_exec() {
	"$SMOLVM" machine exec --name "$name" --timeout 180s --user developer \
		--env XDG_RUNTIME_DIR=/run/user/1000 \
		--env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus -- "$@"
}

ready=0
for _ in $(seq 1 90); do
	if "$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet multi-user.target 2>/dev/null &&
		"$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet user@1000.service 2>/dev/null &&
		[ "$("$SMOLVM" machine exec --name "$name" -- stat -c '%U:%G:%a' /dev/net/tun 2>/dev/null | tr -d '\r')" = 'root:developer:660' ]; then
		ready=1
		break
	fi
	sleep 1
done
[ "$ready" = 1 ] || {
	echo "developer user manager and rootless TUN permissions were not ready after 90 seconds" >&2
	exit 1
}

delegate="$("$SMOLVM" machine exec --name "$name" -- systemctl show user@1000.service --property=Delegate --value | tr -d '\r')"
[ "$delegate" = yes ] || {
	echo "systemd is not delegating the developer user cgroup" >&2
	exit 1
}

info="$(user_exec podman info --format '{{.Host.Security.Rootless}}|{{.Host.RootlessNetworkCmd}}|{{.Host.CgroupManager}}|{{.Host.CgroupsVersion}}')"
[ "$info" = 'true|slirp4netns|systemd|v2' ] || {
	echo "unexpected rootless Podman configuration: $info" >&2
	exit 1
}

for unit in podman.socket netavark-dhcp-proxy.socket netavark-dhcp-proxy.service; do
	if "$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet "$unit" 2>/dev/null; then
		echo "unexpected active API/helper unit: $unit" >&2
		exit 1
	fi
done
if user_exec systemctl --user is-active --quiet podman.socket 2>/dev/null; then
	echo "the rootless Podman API socket is active" >&2
	exit 1
fi

# shellcheck disable=SC2016
user_exec podman run --rm \
	--network=slirp4netns \
	--memory=64m \
	--cpus=0.5 \
	docker.io/library/alpine:3.22 \
	sh -c 'test "$(cat /sys/fs/cgroup/memory.max)" = 67108864 && test "$(cat /sys/fs/cgroup/cpu.max)" = "50000 100000" && wget -qO- http://example.com/ >/dev/null'

# shellcheck disable=SC2016
user_exec sh -lc '
	set -eu
	container=bb-podman-port-check
	podman rm -f "$container" >/dev/null 2>&1 || true
	trap '\''podman rm -f "$container" >/dev/null 2>&1 || true'\'' EXIT
	podman run -d --name "$container" -p 127.0.0.1:18080:80 docker.io/library/nginx:alpine >/dev/null
	for _ in $(seq 1 10); do
		if curl --max-time 3 -fsS http://127.0.0.1:18080/ >/dev/null 2>&1; then
			echo "rootless port mapping works"
			exit 0
		fi
		sleep 1
	done
	echo "rootless Podman did not publish port 18080" >&2
	exit 1
'

echo "$FLAVOR rootless Podman CLI gate passed: uid mapping, cgroups, slirp networking, no API socket"
