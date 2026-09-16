# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# check-flavors: slim slim-sudo

# The negative half of the slim contract. A flavor is defined by what it does
# not carry as much as what it does: a slim image that quietly grew the full
# package tier would pass every positive check and stop being slim. Refuse the
# full image's extras outright.
# shellcheck source=build/check/lib.sh
say "slim does not carry the full image's batteries"
# Library-only packages have no command to look up, so this probes the package
# database rather than PATH for what cannot be seen in PATH.
crun --user root <<'SH'
set -eu
for c in playwright psql sqlite3 rg jq fd nvim tmux git-lfs shellcheck shfmt vi vim bb-backup go; do
	if command -v "$c" >/dev/null 2>&1; then
		echo "slim carries '$c', which belongs to the full image" >&2
		exit 1
	fi
done
# sudo exists only in the sudo flavors; for a plain slim build it must be absent.
case " $FLAVOR " in
	*" slim-sudo "*) ;;
	*)
		command -v sudo >/dev/null 2>&1 && {
			echo "slim carries sudo; only the sudo flavors may" >&2
			exit 1
		}
		;;
esac
for path in /opt/ms-playwright /usr/local/share/bb/bb-backup \
	/usr/local/share/bb/fonts.conf; do
	[ -e "$path" ] && {
		echo "slim carries $path" >&2
		exit 1
	}
done
# No built vi scripts either: the vi/vim wrappers come with neovim, which slim
# does not bake.
grep -q nvim /usr/local/bin/vi 2>/dev/null && {
	echo "slim carries the vi wrapper" >&2
	exit 1
}
for pkg in imagemagick poppler-utils postgresql-client libsqlite3-dev sqlite3 \
	build-essential qpdf webp pngquant; do
	dpkg -s "$pkg" >/dev/null 2>&1 && {
		echo "slim carries the apt package $pkg" >&2
		exit 1
	}
done
printenv FONTCONFIG_FILE >/dev/null 2>&1 && {
	echo "slim sets FONTCONFIG_FILE, which only the full image may" >&2
	exit 1
}
echo "no full-image extras present"
SH

say "slim stays ahead of its size ceiling"
size="$("$ENGINE" image inspect "$img" --format '{{.Size}}')"
# Measured 925MB against full's 2,398MB at first build. A ceiling is a
# regression alarm, not a contract: bump it deliberately when slim grows, and
# investigate whenever the growth is not a bump you know about.
ceiling=1100000000
[ "$size" -le "$ceiling" ] || {
	echo "slim is $size bytes, past the $ceiling ceiling; a full-image extra has grown in" >&2
	exit 1
}
echo "size $(awk "BEGIN{printf \"%.0f MB\", $size/1000000}")"
