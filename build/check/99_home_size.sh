# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo

# Nothing heavy may live in $HOME at first boot: it is volume-backed, and
# whatever is here gets copied in and frozen when the named volume is first
# created.
say "home stays small; build residue here gets frozen into the volume on first boot"
home_kb="$("$ENGINE" run --rm "$img" /bin/bash -c 'du -sk /home/developer' | cut -f1)"
echo "home is ${home_kb}K"
[ "$home_kb" -le 40 ] ||
	{
		echo "home grew past 40K (it should stay near 20K); look for build residue writing into \$HOME (see AGENTS.md)" >&2
		exit 1
	}
