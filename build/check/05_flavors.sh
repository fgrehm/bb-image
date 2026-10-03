#!/bin/sh
# Partials sourced by build/check.sh; shared variables/functions come from lib.sh.
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-scope: repo

say "the manifest drives the published flavor graph and generated targets"
manifest="$root/container/flavors.tsv"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

manifest_flavors="$(awk -F '\t' '$1 !~ /^#/ && NF >= 6 {print $1}' "$manifest" | sort)"
containerfiles="$(for f in "$root"/container/Containerfile.*; do printf '%s\n' "${f##*.}"; done | sort)"
published="$(sh "$root/build/manifest.sh" published | sort)"
known="$(printf '%s\n' "$known_flavors" | tr ' ' '\n' | sed '/^$/d' | sort)"

same_set() {
	[ "$2" = "$3" ] && return 0
	printf '%s\n' "$1" >&2
	printf '%s\n' "$2" >"$tmp/expected"
	printf '%s\n' "$3" >"$tmp/got"
	diff -u "$tmp/expected" "$tmp/got" >&2 || true
	return 1
}

[ -n "$known_flavors" ] || {
	echo "known_flavors is empty" >&2
	exit 1
}
same_set "manifest entries differ from Containerfiles" "$manifest_flavors" "$containerfiles"
same_set "manifest published entries differ from known_flavors" "$published" "$known"

bake="$(sh "$root/build/manifest.sh" bake)"
for flavor in $manifest_flavors; do
	printf '%s\n' "$bake" | grep -q "^target \"$flavor\" {" || {
		echo "generated bake lacks target $flavor" >&2
		exit 1
	}
	parent="$(awk -F '\t' -v f="$flavor" '$1 == f {print $2}' "$manifest")"
	target="$(printf '%s\n' "$bake" | sed -n "/^target \"$flavor\" {/,/^}/p")"
	if [ "$parent" != - ]; then
		printf '%s\n' "$target" | grep -Fq "contexts   = { parent = \"target:$parent\" }" || {
			echo "generated bake target $flavor lacks parent $parent" >&2
			exit 1
		}
	fi
done

matrix="$(sh "$root/build/manifest.sh" matrix)"
printf '%s\n' "$matrix" | jq -e '.include | type == "array"' >/dev/null
matrix_flavors="$(printf '%s\n' "$matrix" | jq -r '.include[].flavor' | sort)"
same_set "generated matrix differs from the published set" "$published" "$matrix_flavors"
printf '%s\n' "$matrix" | jq -e '
  [.include[] | select(
    (.flavor == "full" and .suffix == "" and .smolvm == false and .boot == false) or
    (.flavor == "slim" and .suffix == "-slim" and .smolvm == false and .boot == false) or
    (.flavor == "slim-sudo" and .suffix == "-slim-sudo" and .smolvm == false and .boot == false) or
    (.flavor == "full-sudo" and .suffix == "-full-sudo" and .smolvm == false and .boot == false) or
    (.flavor == "vm" and .suffix == "-vm" and .smolvm == true and .boot == true) or
    (.flavor == "vm-sudo" and .suffix == "-vm-sudo" and .smolvm == true and .boot == true) or
    (.flavor == "exedev" and .suffix == "-exedev" and .smolvm == true and .boot == true) or
    (.flavor == "worker" and .suffix == "-worker" and .smolvm == false and .boot == false) or
    (.flavor == "worker-vm" and .suffix == "-worker-vm" and .smolvm == true and .boot == false)
  )] | length == 9
' >/dev/null

workflow="$root/.github/workflows/publish.yml"
grep -Fq 'fromJSON(needs.matrix.outputs' "$workflow" || {
	echo "publish workflow does not consume the generated matrix" >&2
	exit 1
}
if grep -Eq '^[[:space:]]*(FLAVORS|SMOLVM_FLAVORS|BOOT_GATE_FLAVORS):' "$workflow"; then
	echo "publish workflow still declares hardcoded flavor lists" >&2
	exit 1
fi
echo "manifest, generated bake, matrix, and workflow agree"
