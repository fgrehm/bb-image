# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: vm exedev

say "bb binds loopback by default and only goes routable on the opt-in"
crun <<'SH'
set -eu

port="$(sed -n 's/^BB_SERVER_PORT=//p' /etc/bb/listener.env)"
[ -n "$port" ] || {
	echo "/etc/bb/listener.env carries no BB_SERVER_PORT" >&2
	exit 1
}
hex="$(printf '%04X' "$port")"
pid=

# The unit passes the environment files in this order, and systemd lets the
# later file win per variable. Sourcing them in the same order reproduces the
# merge without needing systemd to run inside a container.
listening() {
	awk -v p=":$hex" 'NR > 1 && $2 ~ p"$" && $4 == "0A" { print $2 }' /proc/net/tcp
}

wait_listening() {
	i=0
	while [ "$i" -lt 60 ]; do
		[ -z "$(listening)" ] || return 0
		i=$((i + 1))
		sleep 0.5
	done
	echo "bb did not listen on port $port within 30s" >&2
	[ -z "${home:-}" ] || tail -5 "$home/bb.log" >&2 || true
	return 1
}

wait_free() {
	i=0
	while [ "$i" -lt 40 ]; do
		[ -n "$(listening)" ] || return 0
		i=$((i + 1))
		sleep 0.5
	done
	echo "port $port stayed bound after bb was stopped" >&2
	return 1
}

stop_bb() {
	[ -z "$pid" ] || kill "$pid" 2>/dev/null || true
	[ -z "$pid" ] || wait "$pid" 2>/dev/null || true
	pid=
	wait_free
}

trap stop_bb EXIT

# 1. Image default only: loopback.
home=/tmp/bb-listener-default
mkdir -p "$home"
set -a
# shellcheck disable=SC1091
. /etc/bb/listener.env
set +a
HOME="$home" bb-app start --no-in-app-updates >"$home/bb.log" 2>&1 &
pid=$!
wait_listening
[ "$(listening)" = "0100007F:$hex" ] || {
	echo "the default listener is $(listening), expected 0100007F:$hex" >&2
	exit 1
}
stop_bb

# 2. Operator opt-in: the later file wins, so bb goes routable.
home=/tmp/bb-listener-optin
mkdir -p "$home"
printf 'BB_SERVER_BIND_HOST=0.0.0.0\n' >/etc/default/bb
set -a
# shellcheck disable=SC1091
. /etc/bb/listener.env
# shellcheck disable=SC1091
. /etc/default/bb
set +a
HOME="$home" bb-app start --no-in-app-updates >"$home/bb.log" 2>&1 &
pid=$!
wait_listening
[ "$(listening)" = "00000000:$hex" ] || {
	echo "the opt-in listener is $(listening), expected 00000000:$hex" >&2
	exit 1
}
stop_bb
rm -f /etc/default/bb

# 3. Anything else is refused at startup, by bb, before it listens.
home=/tmp/bb-listener-invalid
mkdir -p "$home"
if HOME="$home" BB_SERVER_BIND_HOST=10.0.0.1 BB_SERVER_PORT="$port" \
	timeout 20 bb-app start --no-in-app-updates >"$home/bb.log" 2>&1; then
	echo "bb accepted an unsupported BB_SERVER_BIND_HOST" >&2
	exit 1
fi
grep -Fq 'BB_SERVER_BIND_HOST must be "127.0.0.1" or "0.0.0.0"' "$home/bb.log" || {
	echo "bb did not refuse the unsupported bind host with its own error" >&2
	tail -5 "$home/bb.log" >&2 || true
	exit 1
}

echo "listener default is loopback, the opt-in is routable, other hosts are refused"
SH
