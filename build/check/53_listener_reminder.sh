# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full vm exedev

say "listener reminder is image-owned and silent without a terminal"
crun --user developer <<'SH'
set -eu
[ "$(stat -c '%U:%a' /usr/local/bin/bb-listener-reminder)" = root:755 ]
[ -z "$(/usr/local/bin/bb-listener-reminder 2>&1)" ]
for shell in /bin/bash /bin/zsh; do
	[ -z "$(BB_LISTENER_REMINDER=1 "$shell" -c ':' 2>&1)" ]
done
SH

# The reminder only has something to say where the image ships a listener
# default. Container flavors keep the entrypoint's routable listener.
if [ "$FLAVOR" = full ]; then
	say "container flavors never print the VM listener reminder"
	out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		"$img" /bin/bash -ic ':')"
	case "$out" in
	*'bb-image: bb listens'*)
		echo "a container flavor printed the VM listener reminder" >&2
		exit 1
		;;
	esac
fi

# Real-TTY round trips are shared behavior; anchor them to vm instead of
# repeating them on every VM sibling. exedev keeps one run, for its port.
if [ "$FLAVOR" = vm ]; then
	say "interactive terminals explain the loopback listener, and overrides silence it"
	for shell in /bin/bash /bin/zsh; do
		out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
			"$img" "$shell" -ic ':')"
		count="$(printf '%s\n' "$out" | grep -c 'bb-image: bb listens on 127.0.0.1:38886 only')"
		[ "$count" = 1 ] || {
			echo "$shell printed the listener reminder $count times, expected 1" >&2
			exit 1
		}
	done

	out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		--env BB_LISTENER_REMINDER=0 "$img" /bin/bash -ic ':')"
	case "$out" in
	*'bb-image: bb listens'*) exit 1 ;;
	esac

	# The marker is created before the inner interactive shell starts, and the
	# variables expand inside the test container, not in this host script.
	# shellcheck disable=SC2016
	out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		--env XDG_CONFIG_HOME=/tmp/bb-listener-reminder "$img" /bin/sh -c \
		'mkdir -p "$XDG_CONFIG_HOME/bb"; touch "$XDG_CONFIG_HOME/bb/listener-reminder-disabled"; exec /bin/bash -ic :')"
	case "$out" in
	*'bb-image: bb listens'*) exit 1 ;;
	esac

	# A routable listener in the operator file means there is nothing to explain.
	out="$("$ENGINE" run --rm --tty --env MISE_OFFLINE=1 --env MISE_QUIET=1 "$img" /bin/sh -c \
		'printf "BB_SERVER_BIND_HOST=0.0.0.0\n" > /etc/default/bb; exec su -s /bin/bash developer -c "/bin/bash -ic :"')"
	case "$out" in
	*'bb-image: bb listens'*) exit 1 ;;
	esac

	# bb's own env.json outranks the operator file, so the reminder must follow
	# it and point at the command that actually changes the effective value.
	out="$("$ENGINE" run --rm --tty --env MISE_OFFLINE=1 --env MISE_QUIET=1 --env BB_DATA_DIR=/tmp/bb-listener-data \
		"$img" /bin/sh -c \
		'mkdir -p /tmp/bb-listener-data; printf "{\"BB_SERVER_BIND_HOST\":\"127.0.0.1\"}\n" > /tmp/bb-listener-data/env.json; printf "BB_SERVER_BIND_HOST=0.0.0.0\n" > /etc/default/bb; exec su -s /bin/bash developer -c "/bin/bash -ic :"')"
	case "$out" in
	*'bb-image: bb listens'*) ;;
	*)
		echo "the reminder ignored bb's env.json, which outranks /etc/default/bb" >&2
		exit 1
		;;
	esac
	case "$out" in
	*'env.json sets the listener'*'bb-app env set BB_SERVER_BIND_HOST 0.0.0.0'*) ;;
	*)
		echo "the reminder did not explain that env.json outranks /etc/default/bb" >&2
		exit 1
		;;
	esac

	# A routable env.json silences it just like a routable operator file.
	out="$("$ENGINE" run --rm --tty --env MISE_OFFLINE=1 --env MISE_QUIET=1 --env BB_DATA_DIR=/tmp/bb-listener-data \
		"$img" /bin/sh -c \
		'mkdir -p /tmp/bb-listener-data; printf "{\"BB_SERVER_BIND_HOST\":\"0.0.0.0\"}\n" > /tmp/bb-listener-data/env.json; exec su -s /bin/bash developer -c "/bin/bash -ic :"')"
	case "$out" in
	*'bb-image: bb listens'*) exit 1 ;;
	esac
fi

if [ "$FLAVOR" = exedev ]; then
	say "exedev explains its own loopback port"
	out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		"$img" /bin/bash -ic ':')"
	count="$(printf '%s\n' "$out" | grep -c 'bb-image: bb listens on 127.0.0.1:3000 only')"
	[ "$count" = 1 ] || {
		echo "exedev printed the listener reminder $count times for port 3000, expected 1" >&2
		exit 1
	}
fi
