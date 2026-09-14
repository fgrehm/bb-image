# The invariant derived images depend on: the mise data dir is developer-owned
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# and writable, so derived images can add tools and they stay usable. Run with
# --user developer because the check's meaning is the permission the image user
# has, and root passes every test -w with an unconditional yes.
say "mise data dir is writable by the image user; derived images depend on it"
crun --user developer <<'SH'
set -eu
test -w /opt/mise/installs
test -w /opt/mise/shims
for d in /opt/mise/installs/node/*/lib/node_modules; do
	[ -d "$d" ] || continue
	test -w "$d"
done
probe=/opt/mise/installs/.writable-probe
touch "$probe"
rm "$probe"
echo "writable by $(id -un)"
SH
