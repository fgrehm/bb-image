# Partials sourced by build/check.sh via build/check/lib.sh.
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "sudo reminder is image-owned and silent without a terminal"
crun --user developer <<'SH'
set -eu
[ "$(stat -c '%U:%a' /usr/local/bin/bb-sudo-reminder)" = root:755 ]
[ -z "$(/usr/local/bin/bb-sudo-reminder 2>&1)" ]
for shell in /bin/bash /bin/zsh; do
	[ -z "$(BB_SUDO_REMINDER=1 "$shell" -c ':' 2>&1)" ]
done
[ -f /etc/sudoers.d/zz-bb-bootstrap ]
SH

# System rc wiring and suppression are shared foundation behavior. Anchor the
# real-TTY round trips to full instead of repeating them on every sibling.
if [ "$FLAVOR" = full ]; then
	say "human bash/zsh terminals show one reminder; suppression does not change policy"
	for shell in /bin/bash /bin/zsh; do
		for flags in -ic -lic; do
			out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
				--env XDG_CONFIG_HOME=/tmp/bb-reminder-test "$img" "$shell" "$flags" ':')"
			[ "$(printf '%s\n' "$out" | grep -c 'bb-image: bootstrap passwordless sudo')" = 1 ]
		done
		out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
			--env BB_SUDO_REMINDER=0 "$img" "$shell" -ic 'sudo -n -k true')"
		case "$out" in *'bb-image: bootstrap'*) exit 1 ;; esac
		# The outer shell is noninteractive; the marker is created before the
		# inner interactive shell starts, in a clean per-container config dir.
		# Variables in the inline script expand inside the test container.
		# shellcheck disable=SC2016
		out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
			--env XDG_CONFIG_HOME=/tmp/bb-reminder-test "$img" /bin/sh -c \
			'mkdir -p "$XDG_CONFIG_HOME/bb"; touch "$XDG_CONFIG_HOME/bb/sudo-reminder-disabled"; exec "$1" -ic "sudo -n -k true"' sh "$shell")"
		case "$out" in *'bb-image: bootstrap'*) exit 1 ;; esac
	done
	out="$("$ENGINE" run --rm --tty --user developer --security-opt no-new-privileges \
		--env MISE_OFFLINE=1 --env MISE_QUIET=1 --env XDG_CONFIG_HOME=/tmp/bb-reminder-test \
		"$img" /bin/bash -ic ':')"
	printf '%s\n' "$out" | grep -q 'Elevation is blocked'
	out="$("$ENGINE" run --rm --tty --user root --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		"$img" /bin/bash -ic ':')"
	case "$out" in *'bb-image: bootstrap'*) exit 1 ;; esac
	out="$("$ENGINE" run --rm --tty --user root --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		--env XDG_CONFIG_HOME=/tmp/bb-reminder-test "$img" /bin/sh -c \
		'rm /etc/sudoers.d/zz-bb-bootstrap; exec runuser -u developer -- /bin/bash -ic ":"')"
	case "$out" in *'bb-image: bootstrap'*) exit 1 ;; esac

	# Only this newly created test volume is removed; shared home retains the
	# marker across recreation while the image's bootstrap policy resets.
	# Explicit name matters: Podman treats an auto-generated volume as anonymous
	# and --rm removes it, even when subsequently addressed by its generated name.
	volume="bbtest-sudo-reminder-$(date +%s)-$$"
	if "$ENGINE" volume inspect "$volume" >/dev/null 2>&1; then
		echo "test volume already exists: $volume" >&2
		exit 1
	fi
	"$ENGINE" volume create "$volume" >/dev/null
	trap '"$ENGINE" volume rm "$volume" >/dev/null' EXIT
	# shellcheck disable=SC2016
	"$ENGINE" run --rm --user developer -v "$volume:/home/developer" "$img" /bin/sh -c \
		'mkdir -p "$HOME/.config/bb"; touch "$HOME/.config/bb/sudo-reminder-disabled"'
	out="$("$ENGINE" run --rm --tty --user developer --env MISE_OFFLINE=1 --env MISE_QUIET=1 \
		-v "$volume:/home/developer" "$img" /bin/bash -ic 'sudo -n -k true')"
	case "$out" in *'bb-image: bootstrap'*) exit 1 ;; esac
	"$ENGINE" volume rm "$volume" >/dev/null
	trap - EXIT
fi
