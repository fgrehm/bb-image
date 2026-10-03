#!/bin/sh
# make check: runs every verification fragment in build/check/ that applies to
# the requested flavor, in lexical order. Behavioural assertions live there; the
# Containerfile itself only builds. The publish workflow runs this before
# pushing, so a release cannot ship while any fragment fails.
#
# FLAVOR names the image variant under check. A fragment declares what it applies
# to with exactly one header:
#
#   # check-flavors: <flavor>...  an image check, selected for each named flavor
#   # check-scope: repo           a repository check, run once in the full job
#
# A fragment with neither, or with both, is a failure, so nothing can start
# running against a new flavor by accident. Repo checks do not depend on the
# image: running them in every matrix job repeated identical work (gitleaks over
# the same history, the lint pass over the same scripts), so they run once in the
# full job, the only one with those tools baked in. `make check FLAVOR=full` runs
# both halves, and every other flavor runs only its image checks.
#
# Plain docker and podman both work; the only bind mounts are read-only, which
# both engines handle identically.
set -eu
here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/.." && pwd)"
export root

# shellcheck source=build/check/lib.sh
. "$here/check/lib.sh"

# Published flavors are derived from the same graph used by the build and CI.
known_flavors="$(sh "$root/build/manifest.sh" published | tr '\n' ' ')"

# The matrix job that also carries the repo-scope fragments (see the header).
# full is always in the publish matrix, and it is the flavor with gitleaks,
# shfmt and shellcheck baked in, so it is the one that can run all of them.
repo_scope_flavor=full

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
	scope="$(sed -n 's/^# check-scope: //p' "$fragment")"
	[ -z "$decl" ] || [ -z "$scope" ] || {
		echo "$name declares both check-flavors and check-scope" >&2
		exit 1
	}
	[ -n "$decl" ] || [ -n "$scope" ] || {
		echo "$name has neither a check-flavors nor a check-scope declaration" >&2
		exit 1
	}
	# Repo checks run once, anchored to the flavor that carries the tools they
	# need; every other matrix job skips them.
	if [ -n "$scope" ]; then
		[ "$scope" = repo ] || {
			echo "$name declares unknown check scope: $scope" >&2
			exit 1
		}
		if [ "$flavor" = "$repo_scope_flavor" ]; then
			selected="$selected $name"
		fi
		continue
	fi
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
