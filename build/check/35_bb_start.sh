# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo

# bb boots in every published image, and `podman stop` reaches it: the
# entrypoint forwards SIGTERM, bb installs its handler and exits 0. This
# waits for the host daemon to finish starting first — a stop issued during
# startup reports 143 on any revision, because bb has not yet installed its
# handler (documented in AGENTS.md).
say "bb boots behind the entrypoint, and stopping it is a clean shutdown"
# The tests use a fixed name and remove it at the end; a name from a leaked
# earlier run would collide.
name="bb-check-startstop"
trap '"$ENGINE" rm -f "$name" >/dev/null 2>&1' EXIT
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
"$ENGINE" rm -f "$name" >/dev/null
trap - EXIT
echo "started and stopped cleanly"
