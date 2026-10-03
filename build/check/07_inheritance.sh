# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-scope: repo

say "the browser-free base and worker inheritance agree in local and CI builds"
grep -qx 'ARG BASE_IMAGE=localhost/bb-stage-worker:dev' "$root/container/Containerfile.full" || {
	echo "full must inherit worker's Node and browser layers" >&2
	exit 1
}
grep -qx 'ARG BASE_IMAGE=localhost/bb-stage-foundation:dev' "$root/container/Containerfile.slim" || {
	echo "slim must inherit the browser-free foundation" >&2
	exit 1
}
grep -Eq '^[[:space:]]+mise install([[:space:]]|$)' "$root/container/Containerfile.foundation" || {
	echo "foundation must install the shared Node runtime" >&2
	exit 1
}
for flavor in slim worker full; do
	# No second bootstrap install before the real toolset is copied in.
	awk '/^COPY .*mise.*toml/ {exit} /mise install/ {exit 1}' \
		"$root/container/Containerfile.$flavor" || {
		echo "$flavor reinstalls Node before its toolset COPY" >&2
		exit 1
	}
done
awk '/^COPY .*mise.*toml/ { copied=1 } /npm install -g "playwright@/ && copied { exit 1 }' \
	"$root/container/Containerfile.worker" || {
	echo "worker toolset COPY must stay below its expensive browser install" >&2
	exit 1
}

# Exercise the real build dispatcher without downloading or starting an engine.
# Each recipe's declared parent is the independent oracle for build order and
# bake contexts, so changing only one graph fails even when flavor sets agree.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The mock engine expands its own arguments and BUILD_TRACE at execution time.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'set -eu' "recipe='' parent=''" \
	'while [ "$#" -gt 0 ]; do' \
	'  case "$1" in' \
	'    -f) shift; recipe=$1 ;;' \
	'    BASE_IMAGE=*) parent=${1#BASE_IMAGE=} ;;' \
	'  esac' \
	'  shift' 'done' \
	'printf "%s|%s\n" "$recipe" "$parent" >> "$BUILD_TRACE"' >"$tmp/engine"
chmod +x "$tmp/engine"
for recipe in "$root"/container/Containerfile.*; do
	flavor="${recipe##*.}"
	[ "$flavor" = foundation ] && continue
	stage="$flavor"
	expected=
	seen=
	while [ "$stage" != foundation ]; do
		case " $seen " in
		*" $stage "*)
			echo "inheritance cycle at $stage" >&2
			exit 1
			;;
		esac
		seen="$seen $stage"
		parent="$(sed -n 's/^ARG BASE_IMAGE=localhost\/bb-stage-\([^:]*\):dev$/\1/p' "$root/container/Containerfile.$stage")"
		[ -n "$parent" ] && [ -f "$root/container/Containerfile.$parent" ] || {
			echo "$stage has no valid parent recipe" >&2
			exit 1
		}
		bake_parent="$(awk -v target="$stage" '
			$0 == "target \"" target "\" {" { inside=1; next }
			inside && /^}/ { exit }
			inside && /contexts/ { print }
		' "$root/docker-bake.hcl")"
		printf '%s\n' "$bake_parent" | grep -qF "target:$parent\"" || {
			echo "bake parent for $stage does not match its recipe ($parent)" >&2
			exit 1
		}
		expected="container/Containerfile.$stage|localhost/bb-stage-$parent:inheritance${expected:+
$expected}"
		stage="$parent"
	done
	expected="container/Containerfile.foundation|
$expected"
	: >"$tmp/trace"
	(cd "$root" && BUILD_TRACE="$tmp/trace" ENGINE="$tmp/engine" FLAVOR="$flavor" IMAGE=bb TAG=inheritance GH_TOKEN='' \
		sh build/build.sh)
	actual="$(cat "$tmp/trace")"
	[ "$actual" = "$expected" ] || {
		printf '%s\n' "local build order for $flavor differs from its recipe chain" \
			"expected:" "$expected" "actual:" "$actual" >&2
		exit 1
	}
done
echo "one inheritance graph, Node shared once, slim remains browser-free"
