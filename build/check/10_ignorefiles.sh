# .dockerignore and .containerignore are two real files (a symlinked ignore file
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# trades one failure mode for another: not every consumer follows it), so they
# need a sync assertion. .dockerignore carries an exact 2-line header, asserted
# verbatim so it cannot silently become a pattern, then a body that has to equal
# .containerignore.
say "the two ignore files stay in step"
[ "$(head -1 .dockerignore)" = "# NOTE: keep in step with .containerignore (make check asserts it); only this" ] ||
	{
		echo ".dockerignore's first header line drifted" >&2
		exit 1
	}
[ "$(sed -n '2p' .dockerignore)" = "# 2-line header differs between the two files." ] ||
	{
		echo ".dockerignore's second header line drifted" >&2
		exit 1
	}
docker_tail="$(mktemp)"
trap 'rm -rf "$docker_tail"' EXIT
tail -n +3 .dockerignore >"$docker_tail"
if ! diff -u "$docker_tail" .containerignore >/dev/null; then
	echo ".dockerignore's body drifted from .containerignore; keep both in step" >&2
	exit 1
fi
rm -f "$docker_tail"
echo ".dockerignore and .containerignore agree"
