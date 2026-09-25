# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo exedev

# The repo's Containerfile and mise.toml have to agree on the node version; the
# duplication is what keeps a toolset edit from rebuilding the node and bb layers.
say "node version agrees between container/Containerfile and mise.toml"
node_arg="$(sed -n 's/^ARG NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
node_toml="$(sed -n 's/^node = "\(.*\)"$/\1/p' "$root/mise.toml")"
[ "$node_arg" = "$node_toml" ] ||
	{
		echo "node mismatch: Containerfile says '$node_arg', mise.toml says '$node_toml'" >&2
		exit 1
	}
echo "node $node_arg, agreed on both sides"
