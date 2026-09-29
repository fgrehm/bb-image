# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-scope: repo

# The flavor set is written down in five places and kept in step by hand: the
# Containerfiles (the real definition), known_flavors in build/check.sh, the case
# in build/build.sh, the targets in docker-bake.hcl, and the matrix plus FLAVORS
# in the publish workflow. A flavor added to one and forgotten in another is a
# silent gap, which is exactly how a new flavor once shipped with no CI at all,
# so the agreement is asserted rather than trusted.
say "the flavor set agrees across Containerfiles, harness, build, bake, and workflow"
containerfiles="$(for f in "$root"/container/Containerfile.*; do
	name="${f##*.}"
	[ "$name" = foundation ] || printf '%s\n' "$name"
done | sort)"
known="$(sed -n "s/^known_flavors='//p" "$root/build/check.sh" | tr -d "'" | tr ' ' '\n' | sort)"
build="$(sed -n 's/^\([a-z][a-z| -]*\)) .*/\1/p' "$root/build/build.sh" |
	tr '|' '\n' | tr -d ' ' | sort -u)"
bake="$(sed -n 's/^target "\([^"]*\)".*/\1/p' "$root/docker-bake.hcl" |
	grep -vE '^(_common|foundation)$' | sort)"
wf_env="$(sed -n 's/^  FLAVORS: //p' "$root/.github/workflows/publish.yml" | tr ' ' '\n' | sort)"
wf_matrix="$(sed -n 's/^ *- flavor: \([a-z-]*\)$/\1/p' "$root/.github/workflows/publish.yml" | sort)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
same_set() {
	[ "$2" = "$3" ] && return 0
	printf '%s\n' "$1" >&2
	printf '%s\n' "$2" >"$tmp/expected"
	printf '%s\n' "$3" >"$tmp/got"
	diff -u "$tmp/expected" "$tmp/got" >&2 || true
	return 1
}

rc=0
same_set "known_flavors in build/check.sh differs from the Containerfile set" \
	"$containerfiles" "$known" || rc=1
same_set "the case in build/build.sh differs from the Containerfile set" \
	"$containerfiles" "$build" || rc=1
same_set "the targets in docker-bake.hcl differ from the Containerfile set" \
	"$containerfiles" "$bake" || rc=1
same_set "FLAVORS in the publish workflow differs from the Containerfile set" \
	"$containerfiles" "$wf_env" || rc=1
same_set "the publish matrix differs from the Containerfile set" \
	"$containerfiles" "$wf_matrix" || rc=1

# The workflow's host-gate lists are separate, narrower sets; keep them honest
# about being subsets, and keep the boot gate inside the smolvm list, since a
# flavor cannot run a guest gate without smolvm installed on the runner.
gate() {
	sed -n "s/^  $1: //p" "$root/.github/workflows/publish.yml" |
		tr -d '[]"' | tr -d "'" | tr ',' '\n' | sed '/^$/d' | sort
}
smolvm="$(gate SMOLVM_FLAVORS)"
boot="$(gate BOOT_GATE_FLAVORS)"
in_set() {
	for x in $3; do
		printf '%s\n' "$2" | grep -qxF "$x" || {
			echo "$1 names '$x', which is not a published flavor" >&2
			return 1
		}
	done
}
in_set "SMOLVM_FLAVORS" "$containerfiles" "$smolvm" || rc=1
in_set "BOOT_GATE_FLAVORS" "$containerfiles" "$boot" || rc=1
in_set "BOOT_GATE_FLAVORS (must be inside SMOLVM_FLAVORS)" "$smolvm" "$boot" || rc=1
[ -n "$smolvm" ] || {
	echo "SMOLVM_FLAVORS is empty; the workflow conditions would never fire" >&2
	rc=1
}
[ "$rc" = 0 ] || exit 1
echo "one flavor set, agreed everywhere"
