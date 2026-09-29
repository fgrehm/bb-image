# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-scope: repo

# Each stage installs its package inventory from a file, which keeps the list
# diffable on its own. The cost is that a list can be added and never wired into
# a Containerfile (dead, and the author thinks the package ships), or a
# Containerfile can reference a list that was renamed. Assert both directions.
say "every packages inventory is wired into a Containerfile, and every reference resolves"
rc=0
for pkg in "$root"/container/packages-*.txt; do
	name="container/${pkg##*/}"
	grep -qF "$name" "$root"/container/Containerfile.* || {
		echo "$name is not referenced by any Containerfile" >&2
		rc=1
	}
done
grep -hoE 'container/packages-[a-z-]+\.txt' "$root"/container/Containerfile.* | sort -u |
	while IFS= read -r ref; do
		[ -f "$root/$ref" ] || {
			echo "$ref is referenced by a Containerfile but does not exist" >&2
			exit 1
		}
	done || rc=1
[ "$rc" = 0 ] || exit 1
echo "packages inventories are wired in both directions"
