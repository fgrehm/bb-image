# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: slim-sudo full-sudo

# What a sudo flavor sells: the container user can elevate, and only inside
# the container. The first check proves delivery; the second proves the other
# half of the contract, that the standard no-new-privileges launch policy
# renders setuid inert, so a standard run of this image cannot accidentally
# become the sudo run.
say "passwordless sudo works inside the rootless container"
crun <<'SH'
set -eu
[ "$(id -u)" = 1000 ] || {
	echo "expected to start as uid 1000, got $(id -u)" >&2
	exit 1
}
[ "$(sudo -n id -u)" = 0 ] || {
	echo "sudo -n did not reach container root; sudoers rule missing or wrong" >&2
	exit 1
}
sudo -n true
[ "$(stat -c %a /etc/sudoers.d/developer)" = 440 ] || {
	echo "sudoers rule is not mode 0440" >&2
	exit 1
}
[ "$(sudo -n stat -c %U /etc/sudoers.d/developer)" = root ] || {
	echo "sudoers rule is not root-owned" >&2
	exit 1
}
echo "uid 1000 elevates to container root"
SH

say "the standard launch profile keeps sudo inert (no-new-privileges)"
# shellcheck disable=SC2086
"$ENGINE" run --rm --security-opt no-new-privileges "$img" sudo -n true >/dev/null 2>&1 && {
	echo "sudo worked despite no-new-privileges; the launch policy must refuse elevation" >&2
	exit 1
}
echo "elevation refused under no-new-privileges, as it must be"
