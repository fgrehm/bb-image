# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "mise loads automatic updates for the agent CLIs"
crun <<'SH'
set -eu
for tool in claude codex pi opencode grok oh-my-pi; do
	value="$(mise config get "tools.$tool.auto_update")"
	[ "$value" = "true" ] || {
		echo "$tool auto_update is '$value', expected true" >&2
		exit 1
	}
done
echo "all agent CLI shims auto-update from the global config"
SH
