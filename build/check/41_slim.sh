# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: slim

# The whole slim contract in one place: the versions it bakes, the lazy tools it
# still resolves, the batteries it must not carry, and the size ceiling that
# catches a full-image extra growing in.

# The slim equivalent of 40_baked_versions: the Containerfile pins bb and node,
# and the slim toolset file has to carry the same node version the bootstrap
# config installed. Nothing here asserts Playwright; the absence section below
# refuses it.
say "slim baked versions match the Containerfile and its toolset file"
bb_arg="$(sed -n 's/^ARG BB_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
node_arg="$(sed -n 's/^ARG BB_NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
slim_node="$(sed -n 's/^node = "\(.*\)"$/\1/p' "$root/container/mise-slim.toml")"
[ "$node_arg" = "$slim_node" ] ||
	{
		echo "node mismatch: Containerfile says '$node_arg', mise-slim.toml says '$slim_node'" >&2
		exit 1
	}
crun --env BB_VERSION="$bb_arg" --env BB_NODE_VERSION="$node_arg" <<'SH'
set -eu
[ "$(bb --version)" = "$BB_VERSION" ] ||
	{ echo "bb version is $(bb --version), expected $BB_VERSION" >&2; exit 1; }
[ "$(node --version)" = "v$BB_NODE_VERSION" ] ||
	{ echo "node version is $(node --version), expected v$BB_NODE_VERSION" >&2; exit 1; }
config_node="$(sed -n 's/^node = "\(.*\)"$/\1/p' /opt/mise/config.toml)"
[ "$config_node" = "$BB_NODE_VERSION" ] ||
	{ echo "the toolset config says node '$config_node', expected $BB_NODE_VERSION" >&2; exit 1; }
echo "bb and node, agreed on all sides"
SH

# What slim promises beyond booting bb. The pnpm shim is the contract: lazy, so
# it installs on first invocation, and then follows whatever the checked-out
# project declares in its packageManager field. The provider CLIs are declared
# lazy too, so their shims exist at build time and resolve on first use; this
# check only proves the shims resolve rather than downloading each release.

# The first-use path needs the network and, for mise's GitHub calls, the token,
# so this section opts back online the way 80_first_use does.
say "lazy pnpm handoff works"
crun --env MISE_OFFLINE=0 <<'SH'
set -eu
version="$(pnpm --version)"
case $version in
	[0-9]*) echo "pnpm resolves: $version" ;;
	*) echo "pnpm did not produce a version: $version" >&2; exit 1 ;;
esac
SH

say "provider shims and bb resolve in a login shell"
crun <<'SH'
set -eu
for c in bb claude codex pi opencode grok omp pnpm; do
	command -v "$c" >/dev/null &&
		true ||
		{ echo "missing shim: $c" >&2; exit 1; }
done
bash -lc 'command -v bb' >/dev/null && echo "all provider shims present, bb resolves"
SH

# The negative half of the slim contract. A flavor is defined by what it does
# not carry as much as what it does: a slim image that quietly grew the full
# package tier would pass every positive check and stop being slim. Refuse the
# full image's extras outright.
say "slim does not carry the full image's batteries"
# Library-only packages have no command to look up, so this probes the package
# database rather than PATH for what cannot be seen in PATH.
crun --user root <<'SH'
set -eu
for c in playwright psql rg jq fd nvim tmux git-lfs shellcheck shfmt vi vim go; do
	if command -v "$c" >/dev/null 2>&1; then
		echo "slim carries '$c', which belongs to the full image" >&2
		exit 1
	fi
done
for path in /opt/ms-playwright /usr/local/share/bb/fonts.conf; do
	[ -e "$path" ] && {
		echo "slim carries $path" >&2
		exit 1
	}
done
# No built vi scripts either: the vi/vim wrappers come with neovim, which slim
# does not bake.
grep -q nvim /usr/local/bin/vi 2>/dev/null && {
	echo "slim carries the vi wrapper" >&2
	exit 1
}
for pkg in imagemagick poppler-utils postgresql-client \
	build-essential qpdf webp pngquant; do
	dpkg -s "$pkg" >/dev/null 2>&1 && {
		echo "slim carries the apt package $pkg" >&2
		exit 1
	}
done
printenv FONTCONFIG_FILE >/dev/null 2>&1 && {
	echo "slim sets FONTCONFIG_FILE, which only the full image may" >&2
	exit 1
}
echo "no full-image extras present"
SH

say "slim stays ahead of its size ceiling"
size="$("$ENGINE" image inspect "$img" --format '{{.Size}}')"
# Measured 925MB against full's 2,398MB at first build. A ceiling is a
# regression alarm, not a contract: bump it deliberately when slim grows, and
# investigate whenever the growth is not a bump you know about.
ceiling=1100000000
[ "$size" -le "$ceiling" ] || {
	echo "slim is $size bytes, past the $ceiling ceiling; a full-image extra has grown in" >&2
	exit 1
}
echo "size $(awk "BEGIN{printf \"%.0f MB\", $size/1000000}")"
