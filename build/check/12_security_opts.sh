# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-scope: repo

# Payload is shared; the container launch profile is the elevation opt-in.
# Test hack too, since workers cannot use the server-oriented run target.
say "Makefile launch profiles block standard containers and permit VM/sudo profiles"
for flavor in full slim slim-sudo full-sudo vm vm-sudo exedev worker worker-vm; do
	case "$flavor" in
	*-sudo | vm | exedev | worker-vm) want=absent ;;
	*) want=present ;;
	esac
	for target in hack run; do
		case "$target:$flavor" in
		run:worker | run:worker-vm) continue ;;
		esac
		cmd="$(make -C "$root" -n "$target" FLAVOR="$flavor" GH_TOKEN=unused)"
		case "$cmd" in
		*"--security-opt no-new-privileges"*) got=present ;;
		*) got=absent ;;
		esac
		[ "$got" = "$want" ] || {
			echo "make $target FLAVOR=$flavor has no-new-privileges '$got', expected '$want'" >&2
			exit 1
		}
	done
done

say "explicit SECURITY_OPTS overrides still select the container policy"
cmd="$(make -C "$root" -n run FLAVOR=full SECURITY_OPTS= GH_TOKEN=unused)"
case "$cmd" in
*"--security-opt no-new-privileges"*)
	echo "explicit elevation override was ignored" >&2
	exit 1
	;;
esac
cmd="$(make -C "$root" -n run FLAVOR=full-sudo 'SECURITY_OPTS=--security-opt no-new-privileges' GH_TOKEN=unused)"
case "$cmd" in
*"--security-opt no-new-privileges"*) ;;
*)
	echo "explicit no-new-privileges override was ignored" >&2
	exit 1
	;;
esac
echo "default profiles and explicit overrides agree with the elevation policy"
