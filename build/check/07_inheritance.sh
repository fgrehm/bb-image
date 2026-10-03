#!/bin/sh
# shellcheck shell=sh disable=SC2154,SC2148,SC2034
# shellcheck source=build/check/lib.sh
# check-scope: repo

say "manifest parents match recipes and local builds follow the graph"
manifest="$root/container/flavors.tsv"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk -F '\t' '!/^[[:space:]]*#/ && NF >= 6 {print}' "$manifest" >"$tmp/rows"

while IFS="$(printf '\t')" read -r flavor parent published suffix smolvm boot; do
	recipe="$root/container/Containerfile.$flavor"
	[ -f "$recipe" ] || {
		echo "missing $recipe" >&2
		exit 1
	}
	if [ "$parent" = - ]; then
		if grep -q '^ARG BASE_IMAGE=' "$recipe"; then
			echo "$flavor is root but declares BASE_IMAGE" >&2
			exit 1
		fi
	else
		grep -Fqx "ARG BASE_IMAGE=localhost/bb-stage-$parent:dev" "$recipe" || {
			echo "$flavor BASE_IMAGE does not match parent $parent" >&2
			exit 1
		}
	fi
done <"$tmp/rows"

cat >"$tmp/engine" <<'ENGINE'
#!/bin/sh
set -eu
stage=
base=none
while [ "$#" -gt 0 ]; do
	case "$1" in
	-f) stage="${2##*.}"; shift 2 ;;
	--build-arg)
		case "$2" in BASE_IMAGE=*) base="${2#BASE_IMAGE=}" ;; esac
		shift 2
		;;
	*) shift ;;
	esac
done
printf '%s|%s\n' "$stage" "$base" >>"$BUILD_TRACE"
ENGINE
chmod +x "$tmp/engine"

while IFS="$(printf '\t')" read -r flavor _ _ _ _ _; do
	: >"$tmp/actual"
	BUILD_TRACE="$tmp/actual" GH_TOKEN='' ENGINE="$tmp/engine" IMAGE=mock TAG=trace FLAVOR="$flavor" \
		sh "$root/build/build.sh" >/dev/null 2>&1
	: >"$tmp/expected"
	previous=
	for stage in $(sh "$root/build/manifest.sh" stages "$flavor"); do
		if [ -n "$previous" ]; then
			printf '%s|localhost/mock-stage-%s:trace\n' "$stage" "$previous" >>"$tmp/expected"
		else
			printf '%s|none\n' "$stage" >>"$tmp/expected"
		fi
		previous="$stage"
	done
	if ! diff -u "$tmp/expected" "$tmp/actual"; then
		echo "build chain differs from manifest for $flavor" >&2
		exit 1
	fi
done <"$tmp/rows"

echo "recipe parents and build chains agree with the manifest"
