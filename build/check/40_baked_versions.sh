# Baked versions must match the Containerfile's ARGs; the Containerfile only
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# builds and does not assert anything any more, so bb/node/playwright presence in
# the released image is only known by comparing what it starts with against what
# the recipe pinned.
say "baked versions match the Containerfile (bb, node, playwright)"
bb_arg="$(sed -n 's/^ARG BB_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
node_arg="$(sed -n 's/^ARG NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
pw_arg="$(sed -n 's/^ARG PLAYWRIGHT_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
crun --env BB_VERSION="$bb_arg" --env NODE_VERSION="$node_arg" --env PLAYWRIGHT_VERSION="$pw_arg" <<'SH'
set -eu
[ "$(bb --version)" = "$BB_VERSION" ] ||
	{ echo "bb version is $(bb --version), expected $BB_VERSION" >&2; exit 1; }
[ "$(node --version)" = "v$NODE_VERSION" ] ||
	{ echo "node version is $(node --version), expected v$NODE_VERSION" >&2; exit 1; }
[ "$(playwright --version 2>/dev/null | grep -oE 'Version [0-9.]+' | cut -d' ' -f2)" = "$PLAYWRIGHT_VERSION" ] ||
	{ echo "playwright $(playwright --version), expected $PLAYWRIGHT_VERSION" >&2; exit 1; }
echo "bb $BB_VERSION, node v$NODE_VERSION, playwright $PLAYWRIGHT_VERSION, all matching"
SH
