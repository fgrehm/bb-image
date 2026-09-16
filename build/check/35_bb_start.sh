# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-flavors: full slim slim-sudo full-sudo

# bb boots in every published image, and `podman stop` reaches it: the
# entrypoint forwards SIGTERM, bb installs its handler and exits 0. The exit
# code is asserted, not just the stop: a bb killed during the grace period
# reports 143, and a stop issued while it is still starting does too (bb has
# not yet installed its handler on any revision, which is documented in
# AGENTS.md).
say "bb boots behind the entrypoint, and stopping it exits cleanly"

# Unique per invocation, so a colliding name deletes only what this run
# created, never a pre-existing container left by an interrupted run.
name=""
cleanup() {
	[ -n "$name" ] &&
		"$ENGINE" rm -f "$name" >/dev/null 2>&1 ||
		return 0
}
trap cleanup EXIT
name="bb-check-startstop-$$"

"$ENGINE" run -d \
	--name "$name" \
	"$img" >/dev/null

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if "$ENGINE" logs "$name" 2>&1 | grep -q "Host daemon started"; then
		ready=1
		break
	fi
	sleep 1
done
[ "$ready" = 1 ] || {
	echo "bb did not report 'Host daemon started' within 20s" >&2
	exit 1
}
"$ENGINE" stop -t 20 "$name" >/dev/null
code="$("$ENGINE" inspect "$name" --format '{{.State.ExitCode}}')"
[ "$code" = 0 ] || {
	echo "after podman stop, bb exited with $code, expected 0 (see the entrypoint signal notes)" >&2
	exit 1
}
cleanup
trap - EXIT
name=""
echo "started and stopped cleanly"
