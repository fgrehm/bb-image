#!/bin/sh
# The single declaration of the image flavor graph. Containerfile.<flavor>
# stays the readable recipe; this manifest drives build and CI generation.
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
manifest="${MANIFEST:-$root/container/flavors.tsv}"

rows() {
	awk -F '\t' '!/^[[:space:]]*#/ && NF >= 6 && $1 != "" {print}' "$manifest"
}

field() {
	awk -F '\t' -v f="$1" -v c="$2" '!/^[[:space:]]*#/ && $1 == f {print $c}' "$manifest"
}

case "${1:-}" in
stages)
	flavor="${2:-}"
	[ -n "$flavor" ] || {
		echo "usage: manifest.sh stages <flavor>" >&2
		exit 2
	}
	[ -n "$(field "$flavor" 1)" ] || {
		echo "unknown flavor: $flavor (known: $(rows | cut -f1 | tr '\n' ' '))" >&2
		exit 1
	}
	chain=
	stage="$flavor"
	while [ "$stage" != "-" ]; do
		chain="$stage $chain"
		parent="$(field "$stage" 2)"
		[ -n "$parent" ] || {
			echo "manifest has no parent for $stage" >&2
			exit 1
		}
		stage="$parent"
	done
	printf '%s\n' "$chain"
	;;
published)
	rows | awk -F '\t' '$3 == "yes" {print $1}'
	;;
matrix)
	printf '{"include":['
	rows | while IFS="$(printf '\t')" read -r flavor parent published suffix smolvm boot; do
		[ "$published" = yes ] || continue
		[ "$suffix" = "-" ] && suffix=""
		[ "$smolvm" = yes ] && smolvm_json=true || smolvm_json=false
		[ "$boot" = yes ] && boot_json=true || boot_json=false
		[ "${first:-1}" = 1 ] || printf ','
		first=0
		printf '{"flavor":"%s","suffix":"%s","smolvm":%s,"boot":%s}' \
			"$flavor" "$suffix" "$smolvm_json" "$boot_json"
	done
	printf ']}\n'
	;;
bake)
	cat <<'HCL'
variable "BB_VERSION" { default = "" }
variable "BB_NODE_VERSION" { default = "" }
variable "PLAYWRIGHT_VERSION" { default = "" }

target "_common" {
  context = "."
  secret  = ["id=github_token,env=GH_TOKEN"]
  args = {
    BB_VERSION         = BB_VERSION
    BB_NODE_VERSION    = BB_NODE_VERSION
    PLAYWRIGHT_VERSION = PLAYWRIGHT_VERSION
    USERNAME           = "developer"
    BUILD_SCRATCH      = "/tmp/build-scratch"
  }
}
HCL
	rows | while IFS="$(printf '\t')" read -r flavor parent published suffix smolvm boot; do
		if [ "$parent" = "-" ]; then
			printf '\ntarget "%s" {\n  inherits   = ["_common"]\n  dockerfile = "container/Containerfile.%s"\n}\n' \
				"$flavor" "$flavor"
		else
			printf '\ntarget "%s" {\n  inherits   = ["_common"]\n  dockerfile = "container/Containerfile.%s"\n  contexts   = { parent = "target:%s" }\n  args       = { BASE_IMAGE = "parent" }\n}\n' \
				"$flavor" "$flavor" "$parent"
		fi
	done
	;;
*)
	echo "usage: manifest.sh stages <flavor> | published | matrix | bake" >&2
	exit 2
	;;
esac
