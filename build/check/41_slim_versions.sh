# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: slim slim-sudo

# The slim equivalent of 40_baked_versions: the Containerfile pins bb and node,
# and the slim toolset file has to carry the same node version the bootstrap
# config installed. Nothing here asserts Playwright; a slim image does not bake
# it (47_slim_absence refuses it).
say "slim baked versions match the Containerfile and its toolset file"
bb_arg="$(sed -n 's/^ARG BB_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
node_arg="$(sed -n 's/^ARG NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
slim_node="$(sed -n 's/^node = "\(.*\)"$/\1/p' "$root/container/mise-slim.toml")"
[ "$node_arg" = "$slim_node" ] ||
	{
		echo "node mismatch: Containerfile says '$node_arg', mise-slim.toml says '$slim_node'" >&2
		exit 1
	}
crun --env BB_VERSION="$bb_arg" --env NODE_VERSION="$node_arg" <<'SH'
set -eu
[ "$(bb --version)" = "$BB_VERSION" ] ||
	{ echo "bb version is $(bb --version), expected $BB_VERSION" >&2; exit 1; }
[ "$(node --version)" = "v$NODE_VERSION" ] ||
	{ echo "node version is $(node --version), expected v$NODE_VERSION" >&2; exit 1; }
config_node="$(sed -n 's/^node = "\(.*\)"$/\1/p' /opt/mise/config.toml)"
[ "$config_node" = "$NODE_VERSION" ] ||
	{ echo "the toolset config says node '$config_node', expected $NODE_VERSION" >&2; exit 1; }
echo "bb and node, agreed on all sides"
SH
