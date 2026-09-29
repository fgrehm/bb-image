# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-scope: repo

# The launch security profile is derived from FLAVOR in the Makefile: the standard
# flavors get --security-opt no-new-privileges and the flavors that sell elevation
# (the sudo pair, the systemd VM, and exe.dev's init workload) must not, because
# passwordless setuid sudo stops working under it. 48_sudo proves the flag makes
# elevation inert once it is passed; this proves the Makefile passes it to exactly
# the right flavors, which is the half that can drift without anyone noticing.
say "make run chooses no-new-privileges from the flavor, not by accident"
for flavor in full slim slim-sudo full-sudo vm vm-sudo exedev; do
	# GH_TOKEN on the command line keeps make from expanding its `gh auth token`
	# fallback, which would reach the network in a check that is otherwise local.
	cmd="$(make -C "$root" -n run FLAVOR="$flavor" GH_TOKEN=unused 2>/dev/null || true)"
	case "$flavor" in
	*-sudo | vm | exedev) want=absent ;;
	*) want=present ;;
	esac
	case "$cmd" in
	*"--security-opt no-new-privileges"*) got=present ;;
	*) got=absent ;;
	esac
	[ "$got" = "$want" ] || {
		echo "make run FLAVOR=$flavor has no-new-privileges '$got', expected '$want'" >&2
		exit 1
	}
done
echo "no-new-privileges is present for the standard flavors and absent where elevation is sold"
