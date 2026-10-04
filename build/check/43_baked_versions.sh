#!/bin/sh
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

say "baked version manifest, image labels, and bb-image-info agree"
bb_arg="$(sed -n 's/^ARG BB_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
node_arg="$(sed -n 's/^ARG BB_NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
pw_arg="$(sed -n 's/^ARG PLAYWRIGHT_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile.foundation")"
labels="$("$ENGINE" image inspect "$img" --format '{{json .Config.Labels}}')"
printf '%s\n' "$labels" | jq -e --arg expected "$node_arg" '."sh.bb.baked.node" == $expected' >/dev/null || {
	echo "$FLAVOR node baked label is missing or mismatched" >&2
	exit 1
}
case "$FLAVOR" in
full | vm | exedev | worker | worker-vm)
	printf '%s\n' "$labels" | jq -e --arg expected "$pw_arg" '."sh.bb.baked.playwright" == $expected' >/dev/null || {
		echo "$FLAVOR Playwright baked label is missing or mismatched" >&2
		exit 1
	}
	;;
*)
	if printf '%s\n' "$labels" | jq -e 'has("sh.bb.baked.playwright")' >/dev/null; then
		echo "$FLAVOR unexpectedly has a Playwright baked label" >&2
		exit 1
	fi
	;;
esac
case "$FLAVOR" in
full | slim | vm | exedev)
	printf '%s\n' "$labels" | jq -e --arg expected "$bb_arg" '."sh.bb.baked.bb" == $expected' >/dev/null || {
		echo "$FLAVOR bb baked label is missing or mismatched" >&2
		exit 1
	}
	;;
*)
	if printf '%s\n' "$labels" | jq -e 'has("sh.bb.baked.bb")' >/dev/null; then
		echo "$FLAVOR unexpectedly has a bb baked label" >&2
		exit 1
	fi
	;;
esac

crun --env BB_VERSION="$bb_arg" --env BB_NODE_VERSION="$node_arg" --env PLAYWRIGHT_VERSION="$pw_arg" <<'SH'
set -eu
[ -r /usr/local/share/bb/baked-versions ]
[ "$(stat -c '%a' /usr/local/share/bb/baked-versions)" = 644 ]
[ "$(stat -c '%U:%G' /usr/local/share/bb/baked-versions)" = developer:developer ]
info="$(bb-image-info)"
printf '%s\n' "$info" | grep -Fx "node=$BB_NODE_VERSION" >/dev/null
case "$FLAVOR" in
full | vm | exedev | worker | worker-vm)
	printf '%s\n' "$info" | grep -Fx "playwright=$PLAYWRIGHT_VERSION" >/dev/null
	;;
esac
case "$FLAVOR" in
full | slim | vm | exedev)
	printf '%s\n' "$info" | grep -Fx "bb=$BB_VERSION" >/dev/null
	runtime_bb="$(sed -n 's/^running bb package: //p' <<EOF
$info
EOF
)"
	[ "$runtime_bb" = "$BB_VERSION" ] || {
		echo "runtime bb package is '$runtime_bb', expected $BB_VERSION" >&2
		exit 1
	}
	;;
*)
	printf '%s\n' "$info" | grep -Fx 'running bb package: not installed (no bb server in this flavor)' >/dev/null
	;;
esac
printf '%s\n' "$info" | grep -F 'Use bb-app start --bundled' >/dev/null
echo "baked versions and runtime report agree"
SH
