# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# Repository checks, not image checks: they run once, in the full job (see
# build/check.sh), and never touch the image.
# check-scope: repo

# .dockerignore and .containerignore are two real files (a symlinked ignore file
# trades one failure mode for another: not every consumer follows it), so they
# need a sync assertion. .dockerignore carries an exact 2-line header, asserted
# verbatim so it cannot silently become a pattern, then a body that has to equal
# .containerignore.
say "the two ignore files stay in step"
[ "$(head -1 "$root/.dockerignore")" = "# NOTE: keep in step with .containerignore (make check asserts it); only this" ] ||
	{
		echo ".dockerignore's first header line drifted" >&2
		exit 1
	}
[ "$(sed -n '2p' "$root/.dockerignore")" = "# 2-line header differs between the two files." ] ||
	{
		echo ".dockerignore's second header line drifted" >&2
		exit 1
	}
docker_tail="$(mktemp)"
trap 'rm -rf "$docker_tail"' EXIT
tail -n +3 "$root/.dockerignore" >"$docker_tail"
if ! diff -u "$docker_tail" "$root/.containerignore" >/dev/null; then
	echo ".dockerignore's body drifted from .containerignore; keep both in step" >&2
	exit 1
fi
rm -f "$docker_tail"
echo ".dockerignore and .containerignore agree"

# Payload is shared; the container launch profile is the elevation opt-in.
# Test hack too, since workers cannot use the server-oriented run target.
say "Makefile launch profiles block standard containers and permit VM sudo"
for flavor in full slim vm exedev worker worker-vm; do
	case "$flavor" in
	vm | exedev | worker-vm) want=absent ;;
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
cmd="$(make -C "$root" -n run FLAVOR=vm 'SECURITY_OPTS=--security-opt no-new-privileges' GH_TOKEN=unused)"
case "$cmd" in
*"--security-opt no-new-privileges"*) ;;
*)
	echo "explicit no-new-privileges override was ignored" >&2
	exit 1
	;;
esac
echo "default profiles and explicit overrides agree with the elevation policy"
