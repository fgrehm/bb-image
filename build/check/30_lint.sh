# Every script in the repo is formatted and linted, by the baked shfmt and
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# Lints every script in the repo, by the baked shfmt and shellcheck inside the
# image itself; catches a bad edit in fontconfig.sh or in here before the
# slower checks run.
say "scripts pass shfmt and shellcheck"
crun --volume "$root:/src:ro" <<'SH'
set -eu
cd /src
fmt="$(shfmt -d build container 2>&1)" || {
	echo "$fmt" >&2
	exit 1
}
shellcheck build/check.sh build/check/*.sh container/entrypoint.sh container/fontconfig.sh
echo "shfmt and shellcheck ok"
SH
