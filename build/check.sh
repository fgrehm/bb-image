#!/bin/sh
# make check: runs every verification fragment in build/check/ against the built
# image, in lexical order. Behavioural assertions live there; the Containerfile
# itself only builds. The publish workflow runs this before pushing, so a release
# cannot ship while any fragment fails.
#
# Plain docker and podman both work; the only bind mounts are read-only, which
# both engines handle identically.
set -eu
here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/.." && pwd)"
export root

# shellcheck source=build/check/lib.sh
. "$here/check/lib.sh"

fragments='10_ignorefiles.sh
20_versions.sh
30_lint.sh
40_baked_versions.sh
50_shims.sh
55_backup.sh
60_fontconfig.sh
70_chromium.sh
71_chromium_writes.sh
80_first_use.sh
85_agents_md.sh
90_mise_writable.sh
95_token_scan.sh
99_home_size.sh'

printf '%s\n' "$fragments" | while IFS= read -r name; do
	fragment="$here/check/$name"
	[ -f "$fragment" ] || {
		echo "required check fragment is missing: $name" >&2
		exit 1
	}
	# Run each sourced fragment in its own shell. Variables and EXIT traps cannot
	# leak into the next concern, while shared functions from lib.sh remain visible.
	(
		# shellcheck source=/dev/null
		. "$fragment"
	)
done

for fragment in "$here"/check/[0-9][0-9]_*.sh; do
	name="$(basename "$fragment")"
	printf '%s\n' "$fragments" | grep -qxF "$name" || {
		echo "unregistered check fragment is present: $name" >&2
		exit 1
	}
done

printf '\nall checks passed\n'
