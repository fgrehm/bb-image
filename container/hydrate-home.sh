#!/bin/bash
# Hydrate image-managed files into the home volume.
#
# A named volume is seeded from the image exactly once, so anything the image
# owns under $HOME freezes at first boot and later image updates never reach an
# existing volume. This script closes that gap for the files that have to
# evolve: on every container start it compares what the volume carries against
# the hashes this image knows about and replaces our copies, leaving anything
# the user has edited untouched. The registry lives outside the volume, at
# /usr/local/share/bb, because the frozen home copy obviously cannot vouch for
# itself.
#
# Modes:
#   stamp    recompute the hash column of managed.tsv from the sources; build
#            time only, so the shipped registry cannot drift from its sources
#   install  hydrate the home volume; the entrypoint runs this on every start
#
# The entrypoint also runs install at build time once, so a freshly seeded
# volume is already correct even for callers that bypass the entrypoint (make
# hack with a new volume, for example).
#
# Never fails the boot: callers run it without set -e and a hydration problem
# is reported and skipped, not fatal. Writes use a temp file and atomic rename,
# and a user-modified target is never overwritten or deleted.

set -u

share="${BB_MANAGED_SHARE:-/usr/local/share/bb}"
registry="$share/managed.tsv"
prev_file="$share/managed-prev.tsv"
data_dir="${BB_DATA_DIR:-$HOME/.bb}"

# The managed markers. They live here rather than in the snippets so the
# snippet files carry the same text the volume ends up with between them.
open='# bb-image managed >>>'
close='# bb-image managed <<<'

say() { printf '%s\n' "hydrate: $*"; }

hash_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# A target starting .bb/ lives in the bb data dir; everything else in $HOME.
target_path() {
	case $1 in
	.bb/*) printf '%s/%s\n' "$data_dir" "${1#.bb/}" ;;
	*) printf '%s/%s\n' "$HOME" "$1" ;;
	esac
}

# The hashes a target may carry and still be ours: the hash this image ships
# plus everything it replaced, so a volume one or more versions behind updates
# in one step.
known_hashes() {
	local target=$1 current=$2
	printf '%s\n' "$current"
	[ -f "$prev_file" ] &&
		awk -F'\t' -v t="$target" '$1 == t && $2 !~ /^#/ {print $2}' "$prev_file"
	return 0
}

is_known() {
	local h=$1
	shift 1>/dev/null || true
	local k
	for k in "$@"; do
		[ "$h" = "$k" ] && return 0
	done
	return 1
}

extract_block() {
	# Everything between the managed markers, exclusive, as a file.
	awk -v o="$open" -v c="$close" '$0 == o {f = 1; next} $0 == c {f = 0; next} f' "$1"
}

atomic_copy() {
	local source=$1 file=$2 tmp
	tmp=$(mktemp "$file.tmp.XXXXXX") || return 1
	if [ -e "$file" ]; then
		chmod --reference="$file" "$tmp"
	else
		chmod --reference="$source" "$tmp"
	fi
	if cat "$source" >"$tmp" && mv -f "$tmp" "$file"; then
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# Replace the managed block in file with snippet. Atomic via a temp file next
# to the target.
write_block() {
	local file=$1 snippet=$2 tmp
	tmp=$(mktemp "$file.tmp.XXXXXX") || return 1
	chmod --reference="$file" "$tmp"
	awk -v o="$open" -v c="$close" -v snippet="$(cat "$snippet")" '
		BEGIN {n = split(snippet, s, "\n")}
		$0 == o && inst != 1 {print o; for (i = 1; i <= n; i++) print s[i]; inst = 1; next}
		inst == 1 && $0 == c {print c; inst = 2; next}
		inst == 1 {next}
		inst == 2 {inst = 0}
		{print}' "$file" >"$tmp" &&
		mv -f "$tmp" "$file" && return 0
	rm -f "$tmp"
	return 1
}

install_row() {
	local target=$1 mode=$2 source=$3 current=$4
	local path src h block kfile tmp

	[ -n "$target" ] || return 0
	case $target in '#'*) return 0 ;; esac
	if [ -z "$current" ]; then
		say "registry row for $target is unstamped, skipped"
		return 0
	fi

	src="$share/$source"
	if [ ! -f "$src" ]; then
		say "missing source for $target: $src, skipped"
		return 0
	fi

	path=$(target_path "$target")
	mkdir -p "$(dirname "$path")"
	kfile=$(mktemp)
	known_hashes "$target" "$current" >"$kfile"
	mapfile -t known <"$kfile"
	rm -f "$kfile"

	if [ "$mode" = file ]; then
		if [ ! -f "$path" ]; then
			if atomic_copy "$src" "$path"; then
				say "installed $target"
			else
				say "failed to install $target, skipped"
			fi
			return 0
		fi
		h=$(hash_of "$path")
		if is_known "$h" "${known[@]}"; then
			if [ "$h" = "$current" ]; then
				say "$target is current"
			else
				if atomic_copy "$src" "$path"; then
					say "updated $target to the shipped version"
				else
					say "failed to update $target, skipped"
				fi
			fi
			return 0
		fi
		say "$target is user-modified, left untouched"
		return 0
	fi

	# Block mode: only the managed block is ours.
	if ! grep -qxF "$open" "$path" 2>/dev/null; then
		tmp=$(mktemp "$path.tmp.XXXXXX") || {
			say "failed to create a temp file for $target, skipped"
			return 0
		}
		if [ -f "$path" ]; then
			chmod --reference="$path" "$tmp"
		else
			chmod --reference="$src" "$tmp"
		fi
		if { [ ! -f "$path" ] || cat "$path"; } >"$tmp" && {
			printf '\n'
			printf '%s\n' "$open"
			cat "$src"
			printf '%s\n' "$close"
		} >>"$tmp" && mv -f "$tmp" "$path"; then
			say "installed the managed block in $target"
		else
			rm -f "$tmp"
			say "failed to install the managed block in $target, skipped"
		fi
		return 0
	fi
	block=$(mktemp)
	extract_block "$path" >"$block"
	if cmp -s "$block" "$src"; then
		rm -f "$block"
		say "$target block is current"
		return 0
	fi
	h=$(hash_of "$block")
	if is_known "$h" "${known[@]}"; then
		if write_block "$path" "$src"; then
			say "updated the managed block in $target"
		else
			say "failed to update the managed block in $target, skipped"
		fi
	else
		say "$target block is user-modified, left untouched"
	fi
	rm -f "$block"
}

stamp() {
	# Rewrite managed.tsv in place, appending the sha256 of each source. The
	# first three columns pass through untouched, so a stale hash column is
	# replaced rather than trusted.
	[ -f "$registry" ] || {
		say "no registry at $registry, nothing to stamp"
		return 0
	}
	# Clean temps a previously interrupted stamp left behind.
	rm -f "$registry".tmp.* 2>/dev/null || true
	local tmp target mode source hash
	tmp=$(mktemp "$registry.tmp.XXXXXX") || {
		say "stamp: failed to create a temp registry"
		return 1
	}
	while IFS=$'\t' read -r target mode source _rest || [ -n "$target" ]; do
		case $target in
		'')
			# Blank line, passed through.
			printf '\n' >>"$tmp"
			continue
			;;
		'#'*)
			# Header or comment, passed through.
			printf '%s\n' "$target" >>"$tmp"
			continue
			;;
		esac
		src="$share/$source"
		if [ ! -f "$src" ]; then
			say "stamp: missing source $src"
			rm -f "$tmp"
			return 1
		fi
		hash=$(hash_of "$src")
		if [ -z "$hash" ]; then
			say "stamp: failed to hash source $src"
			rm -f "$tmp"
			return 1
		fi
		printf '%s\t%s\t%s\t%s\n' "$target" "$mode" "$source" "$hash" >>"$tmp"
	done <"$registry"
	if mv -f "$tmp" "$registry"; then
		say "stamped $registry"
		return 0
	fi
	rm -f "$tmp"
	say "stamp: failed to replace $registry"
	return 1
}

install() {
	[ -f "$registry" ] || {
		say "no registry at $registry, nothing to do"
		return 0
	}
	local target mode source current
	while IFS=$'\t' read -r target mode source current _rest || [ -n "$target" ]; do
		install_row "$target" "$mode" "$source" "$current"
	done <"$registry"
}

case "${1:-install}" in
stamp) stamp ;;
install) install ;;
*)
	say "usage: hydrate-home.sh [stamp|install]"
	exit 2
	;;
esac
