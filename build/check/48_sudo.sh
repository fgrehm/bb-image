# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo vm vm-sudo exedev worker worker-vm

# Sudo is a shared payload. VM images normally boot as root, so always exercise
# the actual developer account, not the image's default user. Container launch
# profiles choose whether that account can use the inherited setuid grant.
say "every flavor carries working passwordless sudo for developer"
crun --user developer <<'SH'
set -eu
[ "$(id -u)" = 1000 ]
[ "$(sudo -n id -u)" = 0 ] || {
	echo "developer cannot elevate; sudoers rule missing or wrong" >&2
	exit 1
}
sudo -n visudo -c
[ "$(stat -c %a /etc/sudoers.d/developer)" = 440 ]
[ "$(stat -c %U /etc/sudoers.d/developer)" = root ]
echo "developer elevates with the validated root-owned sudoers grant"
SH

say "no-new-privileges blocks the same developer grant"
# Execute an assertion inside a successfully started container, so an engine
# failure cannot be mistaken for sudo correctly refusing elevation.
crun --user developer --security-opt no-new-privileges <<'SH'
set -eu
grep -Eq '^NoNewPrivs:[[:space:]]+1$' /proc/self/status
if sudo -n true >/dev/null 2>&1; then
	echo "sudo worked despite no-new-privileges" >&2
	exit 1
fi
echo "elevation refused under the standard container launch policy"
SH
