# Runtime view of the Containerfile's fontconfig override: the shipped
# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh

# fonts.conf has to match Debian's (drift guard, run first), fc-cache must name
# exactly the xdg cache, and fc-match has to agree with the distro file family
# for family including the mono alias, which lives inline in fonts.conf and
# nowhere in conf.d. LC_ALL=C keeps the grep independent of the image's or the
# caller's locale.
say "fontconfig override: drift guard, single xdg cache directory, match parity"
"$root/container/fontconfig.sh" check
crun <<'SH'
set -eu
runtime_out="$(XDG_CACHE_HOME=/tmp/fc LC_ALL=C fc-cache -v 2>&1)"
cache_dirs="$(printf '%s\n' "$runtime_out" | grep -i 'cache directory' | sed 's/:.*//' | sort -u)"
[ -n "$cache_dirs" ] || { echo "fc-cache reported no cache directories" >&2; exit 1; }
[ "$cache_dirs" = "/tmp/fc/fontconfig" ] ||
	{
		echo "unexpected cache directory list; expected only /tmp/fc/fontconfig, got:" >&2
		echo "$cache_dirs" >&2
		exit 1
	}
for f in mono monospace serif sans-serif "sans serif" sans emoji; do
	s=$(FONTCONFIG_FILE=/etc/fonts/fonts.conf fc-match "$f")
	o=$(fc-match "$f")
	[ "$s" = "$o" ] || { echo "MISMATCH $f: stock=$s override=$o" >&2; exit 1; }
done
echo "fc-cache names one xdg cache directory; fc-match parity ok"
SH
