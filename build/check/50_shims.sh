# Debian's /etc/profile resets PATH, which drops the mise shims; the profile fix
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# in the container image puts them back. The assertion runs inside `bash -lc`
# because a non-login shell inherits image ENV PATH and would pass even if the
# profile script were deleted.
say "login shell keeps the shims that /etc/profile would otherwise drop"
crun <<'SH'
set -eu
exec bash -lc 'command -v rg >/dev/null && echo "login shell resolves rg: $(command -v rg)"'
SH

say "baked tools all run"
crun <<'SH'
set -eu
for c in "rg --version" "jq --version" "fd --version" "shfmt --version" \
	"shellcheck --version" "tmux -V" "git-lfs --version"; do
	$c >/dev/null
	echo "ok: $c"
done
# vi/vim must be the wrapper scripts in /usr/local/bin, never shims; mise
# dispatches on the tool name in argv[0], so a shim reached as "vim" fails with
# "vim is not a valid shim".
if ls /opt/mise/shims | grep -qE '^(vi|vim)$'; then
	echo "unexpected vi/vim shim present" >&2
	exit 1
fi
vi --version | head -1
SH
