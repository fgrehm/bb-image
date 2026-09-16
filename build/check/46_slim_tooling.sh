# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: slim slim-sudo

# What slim promises beyond booting bb. The pnpm shim is the contract: lazy, so
# it installs on first invocation, and then follows whatever the checked-out
# project declares in its packageManager field. The provider CLIs are declared
# lazy too, so their shims exist at build time and resolve on first use; this
# check only proves the shims resolve rather than downloading each release.

# The first-use path needs the network and, for mise's GitHub calls, the token,
# so this fragment opts back online the way 80_first_use does.
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
