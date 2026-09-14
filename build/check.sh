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

for fragment in "$here"/check/[0-9][0-9]_*.sh; do
	# shellcheck source=/dev/null
	. "$fragment"
done

printf '\nall checks passed\n'
