#!/bin/sh
# Host-only gate for the vm image's systemd contract. This requires KVM/libkrun
# and intentionally does not run under `make check` inside bb-image.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SMOLVM="${SMOLVM:-smolvm}"
ENGINE="${ENGINE:-podman}"
IMAGE="${IMAGE:-bb}"
FLAVOR="${FLAVOR:-vm}"
TAG="${TAG:-$FLAVOR}"
name="bb-systemd-check-$$"
tmp="${TMPDIR:-/tmp}/bb-systemd-check-$$"
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

stop_cleanly() {
	status=0
	output="$(timeout 30 "$SMOLVM" machine stop --name "$name" 2>&1)" || status=$?
	printf '%s\n' "$output"
	running=0
	[ "$status" -eq 0 ] || {
		echo "smolvm machine stop failed with status $status" >&2
		return 1
	}
	if printf '%s\n' "$output" | grep -q 'shutdown acknowledgment failed'; then
		echo "smolvm stopped the machine without a clean shutdown acknowledgment" >&2
		return 1
	fi
}

dump_guest_diagnostics() {
	echo "--- bb.service status ---" >&2
	"$SMOLVM" machine exec --name "$name" -- \
		systemctl status bb.service --no-pager -l >&2 2>&1 || true
	echo "--- bb.service journal ---" >&2
	"$SMOLVM" machine exec --name "$name" -- \
		journalctl -b -u bb.service --no-pager -n 100 >&2 2>&1 || true
	echo "--- listening sockets ---" >&2
	"$SMOLVM" machine exec --name "$name" -- ss -ltnp >&2 2>&1 || true
}

command -v "$SMOLVM" >/dev/null 2>&1 || {
	echo "smolvm is required on the host" >&2
	exit 1
}
command -v "$ENGINE" >/dev/null 2>&1 || {
	echo "$ENGINE is required to export the image" >&2
	exit 1
}

marker="$($ENGINE image inspect "$IMAGE:$TAG" --format '{{ index .Config.Labels "sh.bb.flavor" }}')"
case "$FLAVOR" in
vm | vm-sudo) ;;
*)
	echo "unsupported VM flavor: $FLAVOR (expected vm or vm-sudo)" >&2
	exit 1
	;;
esac
[ "$marker" = "$FLAVOR" ] || {
	echo "$IMAGE:$TAG is marked '$marker', expected $FLAVOR" >&2
	exit 1
}

"$ENGINE" save "$IMAGE:$TAG" -o "$archive"
"$SMOLVM" machine create --name "$name" \
	--smolfile "$root/examples/smolvm-systemd/Smolfile" \
	--image "$archive"
created=1

timeout 120 "$SMOLVM" machine start --name "$name"
running=1

ready=0
for _ in $(seq 1 90); do
	if "$SMOLVM" machine exec --name "$name" -- \
		curl -fsS http://127.0.0.1:38886/api/v1/hosts >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 1
done
[ "$ready" = 1 ] || {
	echo "bb API did not become healthy within 90 seconds" >&2
	exit 1
}

[ "$("$SMOLVM" machine exec --name "$name" -- ps -p 1 -o comm= | tr -d '[:space:]')" = systemd ] || {
	echo "systemd is not workload PID 1" >&2
	exit 1
}
"$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet multi-user.target
"$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet bb.service
bb_pid="$("$SMOLVM" machine exec --name "$name" -- systemctl show --property MainPID --value bb.service | tr -d '[:space:]')"
[ -n "$bb_pid" ] && [ "$bb_pid" != 0 ] || {
	echo "bb.service has no main process" >&2
	exit 1
}
[ "$("$SMOLVM" machine exec --name "$name" -- readlink "/proc/$bb_pid/cwd" | tr -d '\r')" = /home/developer ] || {
	echo "bb.service did not start in /home/developer" >&2
	exit 1
}
# hostname expands inside the guest shell.
# shellcheck disable=SC2016
"$SMOLVM" machine exec --name "$name" -- sh -c 'getent hosts "$(hostname)" >/dev/null' || {
	echo "the guest hostname does not resolve locally" >&2
	exit 1
}
machine_id="$("$SMOLVM" machine exec --name "$name" -- cat /etc/machine-id | tr -d '[:space:]')"
[ -n "$machine_id" ] || {
	echo "systemd did not initialize /etc/machine-id" >&2
	exit 1
}
case "$FLAVOR" in
vm)
	if "$SMOLVM" machine exec --name "$name" -- command -v sudo >/dev/null 2>&1; then
		echo "the standard VM unexpectedly contains sudo after boot" >&2
		exit 1
	fi
	;;
vm-sudo)
	"$SMOLVM" machine exec --name "$name" -- \
		su -s /bin/sh developer -c 'sudo -n true'
	;;
esac
# HOME expands inside the guest's developer shell, not in this host script.
# shellcheck disable=SC2016
"$SMOLVM" machine exec --name "$name" -- \
	su -s /bin/sh developer -c 'mkdir -p "$HOME/.bb" && printf phase0 > "$HOME/.bb/vm-persistence-probe"'

stop_cleanly
timeout 120 "$SMOLVM" machine start --name "$name"
running=1

ready=0
for _ in $(seq 1 90); do
	if "$SMOLVM" machine exec --name "$name" -- systemctl is-active --quiet bb.service 2>/dev/null &&
		"$SMOLVM" machine exec --name "$name" -- \
			curl -fsS http://127.0.0.1:38886/api/v1/hosts >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 1
done
[ "$ready" = 1 ] || {
	echo "bb service and API did not recover within 90 seconds after restart" >&2
	dump_guest_diagnostics
	exit 1
}
"$SMOLVM" machine exec --name "$name" -- \
	grep -qx phase0 /home/developer/.bb/vm-persistence-probe
[ "$("$SMOLVM" machine exec --name "$name" -- cat /etc/machine-id | tr -d '[:space:]')" = "$machine_id" ] || {
	echo "machine identity changed across restart" >&2
	exit 1
}

stop_cleanly

echo "$FLAVOR systemd gate passed: boot, target, bb, API, persistence, restart, and bounded shutdown"
