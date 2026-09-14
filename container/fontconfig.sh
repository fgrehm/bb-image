#!/bin/sh
# Drift guard and regeneration for fonts.conf, kept next to the file they guard.
# fonts.conf is Debian's /etc/fonts/fonts.conf with the system cache directories
# removed; a font package bump that moves the distro file would otherwise silently
# drop font directories or alias rules. Nothing verification-shaped runs in the
# Containerfile any more: `make check` runs `fontconfig.sh check` before a release
# is pushed, and `make fonts-regen` rewrites fonts.conf from the distro's.
#
# The image must exist first: both modes compare against, or read from, the distro
# file inside it.
set -eu

: "${ENGINE:=podman}" "${IMAGE:=bb}" "${TAG:=dev}"
img="$IMAGE:$TAG"
dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
mode="${1:-check}"

case "$mode" in
check)
	# Optional second arg: a candidate file (used by regen) replaces the in-image
	# shipped file as the body under test; it is bind-mounted read-only and pointed
	# at through BODY. Without it, check validates the image as built.
	vols=""
	body_env=""
	if [ -n "${2:-}" ]; then
		case "$2" in /*) ;; *)
			echo "candidate path must be absolute" >&2
			exit 64
			;;
		esac
		vols="--volume $2:/run/candidate/fonts.conf:ro"
		body_env="--env BODY=/run/candidate/fonts.conf"
	fi
	run() {
		# --interactive is not optional: without it the engine gives bash an
		# empty stdin and bash -s exits 0 without running anything, a silent
		# pass. See build/check.sh's crun for the same trap.
		# shellcheck disable=SC2086
		"$ENGINE" run --rm --interactive $vols $body_env "$img" /bin/bash -s <<'SH'
set -eu
body="${BODY:-/usr/local/share/bb/fonts.conf}"

# Strip comments, blank lines and indentation from both sides, so distro rewording
# is not drift, and normalise the two elements that differ on purpose. The awk is a
# small comment state machine because the obvious sed range (`/<!--/,/-->/ d`)
# swallows content: on a self-contained `<!-- ... -->` line it starts a range whose
# end is only searched on the following lines.
norm() {
	awk '
		BEGIN { c = 0 }
		{
			s = $0
			o = ""
			while (s != "") {
				if (c) {
					p = index(s, "-->")
					if (p == 0) s = ""
					else { s = substr(s, p + 3); c = 0 }
				} else {
					p = index(s, "<!--")
					if (p == 0) { o = o s; s = "" }
					else { o = o substr(s, 1, p - 1); s = substr(s, p + 4); c = 1 }
				}
			}
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", o)
			if (o != "") print o
		}
	' "$1" \
		| sed 's|^<description>.*|<description/>|; s|^<include ignore_missing="yes">conf.d</include>$|<include ignore_missing="yes">MISSING-INCLUDE</include>|; s|^<include ignore_missing="yes">/etc/fonts/conf.d</include>$|<include ignore_missing="yes">MISSING-INCLUDE</include>|'
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
norm /etc/fonts/fonts.conf | grep -v '^<cachedir' >"$tmp/distro"
norm "$body" | grep -v '^<cachedir' >"$tmp/shipped"
if ! diff -u "$tmp/distro" "$tmp/shipped"; then
	echo "fonts.conf no longer matches /etc/fonts/fonts.conf" >&2
	echo "regenerate it: make fonts-regen" >&2
	exit 1
fi

cachedir="$(norm "$body" | grep '^<cachedir' || true)"
if [ "$cachedir" != '<cachedir prefix="xdg">fontconfig</cachedir>' ]; then
	echo "fonts.conf must declare exactly one cache directory, the xdg one;" \
		"found [$cachedir]" >&2
	exit 1
fi

grep -qF '<include ignore_missing="yes">/etc/fonts/conf.d</include>' "$body" ||
	{ echo "fonts.conf must include /etc/fonts/conf.d by absolute path" >&2; exit 1; }

echo "fonts.conf matches /etc/fonts/fonts.conf, single xdg cachedir"
SH
	}
	run
	;;
regen)
	# Debian's file with three changes: the description, an absolute conf.d
	# include, and the cache directory list (the distro's cache directory
	# comment goes with its <cachedir> lines). The shipped header comment is
	# carried over from the current file, and the image's own cache block is
	# spliced in where the distro's used to sit.
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	"$ENGINE" run --rm "$img" /bin/sed \
		-e 's|<description>.*</description>|<description>bb-image fontconfig (xdg cache only)</description>|' \
		-e 's|<include ignore_missing="yes">conf.d</include>|<include ignore_missing="yes">/etc/fonts/conf.d</include>|' \
		-e '/Font cache directory list/d' -e '/<cachedir>/d' \
		/etc/fonts/fonts.conf >"$tmp/distro"

	# Drop the distro preamble (everything before <fontconfig>), which carries
	# Debian's prose; our header comes from the current file instead.
	sed -n '/^<fontconfig>/,$p' "$tmp/distro" | awk -v cache="$dir/fonts-cache.inc" '
		!done && /^<config>$/ {
			while ((getline line < cache) > 0) print line
			close(cache)
			done = 1
		}
		{ print }
	' >"$tmp/body"
	awk '/^<fontconfig>/ { exit } { print }' "$dir/fonts.conf" >"$tmp/header"
	cat "$tmp/header" "$tmp/body" >"$dir/fonts.conf.new"

	# The candidate is validated through the same guard `make check` uses, not
	# against the image's stale shipped file; the diff and reason the guard
	# writes on failure are forwarded so the failure is diagnosable without
	# hand-inspecting fonts.conf.new.
	if ! guard_out="$("${0}" check "$dir/fonts.conf.new")"; then
		echo "$guard_out" | sed '/^$/d'
		echo "regeneration produced a guard-failing file, leaving fonts.conf untouched; inspect $dir/fonts.conf.new" >&2
		exit 1
	fi
	echo "$guard_out"
	mv "$dir/fonts.conf.new" "$dir/fonts.conf"
	echo "fonts.conf regenerated; review the diff before committing"
	;;
*)
	echo "usage: fontconfig.sh [check|regen]" >&2
	exit 64
	;;
esac
