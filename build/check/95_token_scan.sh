# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo exedev

# Three exit codes, because the scan has to fail closed on its own failures:
# 0 means no match, 3 means a file matched (a leak, printed as hits), anything
# else (grep read errors, a vanished subtree mid-scan) is a scan failure and
# must fail the check rather than print "no matches". The token reaches grep
# through stdin (-f -), so it never lands in an environment, on a command
# line, or on disk. The scan cannot see bytes in a lower layer that a later
# layer deleted, since that content is whiteouted rather than removed; the
# sentinel procedure in AGENTS.md is the only check that decompresses the
# layers themselves, and is the right tool for that blind spot. Running as
# uid 0 (like the old build-time guard) shrinks the unreadable-path blind
# spot to 0700 dirs; stderr's permission noise is exactly why an unreadable
# path is an exit 2, not silence.
say "build token does not appear anywhere in the image filesystem"
if [ -n "${GH_TOKEN:-}" ]; then
	leak_rc=0
	# SC2016 is deliberate: the payload is single-quoted so the outer shell does not
	# expand variables meant for the container.
	# shellcheck disable=SC2016
	leak="$(printf '%s' "$GH_TOKEN" | "$ENGINE" run --rm --interactive --user 0 "$img" /bin/bash -c '
		set -eu
		tmp=$(mktemp -d)
		trap "rm -rf $tmp" EXIT
		rc=0
		grep -rlF --binary-files=text -f - / --exclude-dir=proc --exclude-dir=sys --exclude-dir=dev --exclude-dir=run 2>/dev/null >"$tmp/hits" || rc=$?
		case $rc in
			0|1) ;;
			*) echo "grep exited $rc (unreadable or errored subtree)" >&2; exit 2 ;;
		esac
		if [ -s "$tmp/hits" ]; then
			head -5 "$tmp/hits"
			exit 3
		fi
		echo no-leak
	')" || leak_rc=$?
	if [ "$leak_rc" -eq 3 ]; then
		echo "build token found on disk:" >&2
		echo "$leak" >&2
		exit 1
	fi
	[ "$leak_rc" -eq 0 ] ||
		{
			echo "token scan failed with status $leak_rc; that is a scan error, not a clean image" >&2
			exit 1
		}
	echo "no matches"
else
	echo "skipped, no GH_TOKEN supplied"
fi
