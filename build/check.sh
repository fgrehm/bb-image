#!/bin/sh
# make check: runs every verification fragment in build/check/ that declares the
# requested flavor, in lexical order. Behavioural assertions live there; the
# Containerfile itself only builds. The publish workflow runs this before
# pushing, so a release cannot ship while any fragment fails.
#
# FLAVOR names the image variant under check (full today, slim and friends as
# they land). Each fragment carries a `# check-flavors:` declaration listing the
# flavors it applies to; a fragment without one is a failure, so nothing can
# start running against a new flavor by accident.
#
# Plain docker and podman both work; the only bind mounts are read-only, which
# both engines handle identically.
set -eu
here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/.." && pwd)"
export root

# shellcheck source=build/check/lib.sh
. "$here/check/lib.sh"

# Flavors the harness knows about. Grows as the Containerfile grows targets;
# a flavor listed here without a matching image is caught by the run itself,
# while an unknown flavor below means a typo in a fragment declaration.
known_flavors='full slim slim-sudo full-sudo vm vm-sudo exedev'

flavor="${FLAVOR:-full}"
export FLAVOR="$flavor"

# Identity gate: every variant stage stamps sh.bb.flavor, and the runner
# refuses an image marked as another flavor. An old image (built before the
# marker existed) is as useless for verification as a mismatched one.
marker="$($ENGINE image inspect "$img" --format '{{ index .Config.Labels "sh.bb.flavor" }}')"
[ "$marker" = "$flavor" ] || {
	echo "image $img is marked '$marker' (or unmarked), but $flavor checks were requested; build with make build FLAVOR=$flavor TAG=$TAG" >&2
	exit 1
}
case " $known_flavors " in
*" $flavor "*) ;;
*)
	echo "unknown check flavor: $flavor (known flavors: $known_flavors)" >&2
	exit 1
	;;
esac

selected=
for fragment in "$here"/check/[0-9][0-9]_*.sh; do
	name="$(basename -- "$fragment")"
	decl="$(sed -n 's/^# check-flavors: //p' "$fragment")"
	[ -n "$decl" ] || {
		echo "fragment has no check-flavors declaration: $name" >&2
		exit 1
	}
	# Every declared flavor has to be known, so a typo cannot silently drop a
	# check from every profile at once.
	# shellcheck disable=SC2086
	for declared in $decl; do
		case " $known_flavors " in
		*" $declared "*) ;;
		*)
			echo "$name declares unknown flavor: $declared" >&2
			exit 1
			;;
		esac
	done
	case " $decl " in
	*" $flavor "*) selected="$selected $name" ;;
	esac
done
[ -n "$selected" ] || {
	echo "no check fragments apply to flavor: $flavor" >&2
	exit 1
}

# shellcheck disable=SC2086
for name in $selected; do
	fragment="$here/check/$name"
	# Run each sourced fragment in its own shell. Variables and EXIT traps cannot
	# leak into the next concern, while shared functions from lib.sh remain visible.
	(
		# shellcheck source=/dev/null
		. "$fragment"
	)
done

printf '\nall checks passed\n'
