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
case "$FLAVOR" in
vm | exedev) ;;
*)
	echo "unsupported VM flavor: $FLAVOR" >&2
	exit 1
	;;
esac
port=38886
smolfile="$root/examples/smolvm-systemd/Smolfile"
if [ "$FLAVOR" = exedev ]; then
	port=3000
	smolfile="$root/examples/exedev/Smolfile"
fi
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

# The examples pick a host port that is unlikely to be taken, and the gate's own
# assertions run inside the guest, so the mapping is only for a local publish.
# When the host port is busy anyway, rewrite the host side of the example in a
# temp copy; the guest port stays whatever the flavor ships.
if [ -n "${SMOLVM_HOST_PORT:-}" ]; then
	case "$SMOLVM_HOST_PORT" in
	*[!0-9]*)
		echo "SMOLVM_HOST_PORT must be a port number, got '$SMOLVM_HOST_PORT'" >&2
		exit 1
		;;
	esac
	rewritten="$tmp/Smolfile"
	sed "s/^ports = \[\"[0-9][0-9]*:$port\"\]/ports = [\"$SMOLVM_HOST_PORT:$port\"]/" \
		"$smolfile" >"$rewritten"
	grep -qx "ports = \[\"$SMOLVM_HOST_PORT:$port\"\]" "$rewritten" || {
		echo "could not rewrite the host port in $smolfile" >&2
		exit 1
	}
	smolfile="$rewritten"
fi

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
[ "$marker" = "$FLAVOR" ] || {
	echo "$IMAGE:$TAG is marked '$marker', expected $FLAVOR" >&2
	exit 1
}

"$ENGINE" save "$IMAGE:$TAG" -o "$archive"
"$SMOLVM" machine create --name "$name" \
	--smolfile "$smolfile" \
	--image "$archive"
created=1

timeout 120 "$SMOLVM" machine start --name "$name"
running=1

ready=0
for _ in $(seq 1 90); do
	if "$SMOLVM" machine exec --name "$name" -- \
		curl -fsS "http://127.0.0.1:$port/api/v1/hosts" >/dev/null 2>&1; then
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
"$SMOLVM" machine exec --name "$name" -- \
	su -s /bin/sh developer -c 'sudo -n true'

# The only place the real systemd EnvironmentFile= merge is exercised: the
# image default keeps bb on loopback, and the operator opt-in in
# /etc/default/bb (read after it) turns the listener routable until it is
# removed again. Every restart has to come back healthy on the new address.
cat >"$tmp/listener.sh" <<'SH'
set -eu

hex="$(printf '%04X' "$BB_PORT")"
# /proc/net/tcp rather than ss, which the guest does not carry.
sockets() {
	awk -v p=":$hex" 'NR > 1 && $2 ~ p"$" && $4 == "0A" { print $2 }' /proc/net/tcp | sort -u
}

wait_api() {
	i=0
	while [ "$i" -lt 60 ]; do
		if curl -fsS "http://127.0.0.1:$BB_PORT/api/v1/hosts" >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	echo "bb API did not answer on 127.0.0.1:$BB_PORT within 60s" >&2
	return 1
}

[ "$(sockets)" = "0100007F:$hex" ] || {
	echo "expected only the loopback listener on port $BB_PORT on first boot, got: $(sockets)" >&2
	exit 1
}

printf 'BB_SERVER_BIND_HOST=0.0.0.0\n' >/etc/default/bb
systemctl restart bb.service
wait_api
case "$(sockets)" in
*"00000000:$hex"*) ;;
*)
	echo "the opt-in did not make the listener routable: $(sockets)" >&2
	exit 1
	;;
esac

rm -f /etc/default/bb
systemctl restart bb.service
wait_api
[ "$(sockets)" = "0100007F:$hex" ] || {
	echo "removing the opt-in did not restore the loopback listener, got: $(sockets)" >&2
	exit 1
}

echo "listener: loopback by default, routable on opt-in, loopback after opt-out"
SH
"$SMOLVM" machine exec --name "$name" -e "BB_PORT=$port" -- sh -c "$(cat "$tmp/listener.sh")"

case "$FLAVOR" in
exedev)
	"$SMOLVM" machine exec --name "$name" -- test -x /usr/sbin/sshd
	"$SMOLVM" machine exec --name "$name" -- sh -c '! systemctl is-active --quiet ssh.service'
	"$SMOLVM" machine exec --name "$name" -- test ! -e /etc/systemd/system/multi-user.target.wants/ssh.service
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
			curl -fsS "http://127.0.0.1:$port/api/v1/hosts" >/dev/null 2>&1; then
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
"$SMOLVM" machine exec --name "$name" -- \
	su -s /bin/sh developer -c 'sudo -n true'
[ "$("$SMOLVM" machine exec --name "$name" -- cat /etc/machine-id | tr -d '[:space:]')" = "$machine_id" ] || {
	echo "machine identity changed across restart" >&2
	exit 1
}

stop_cleanly

echo "$FLAVOR systemd gate passed: boot, target, bb, API, listener default and opt-in, bootstrap sudo, persistence, restart, and bounded shutdown"
