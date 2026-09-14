#!/bin/sh
# Behavioural checks against a built image. The Containerfile carries no
# verification RUNs; every assertion lives here, and the publish workflow runs this
# script before an image is pushed, so a release cannot ship while anything here
# fails. Run it by hand as `make check`, or as `make ci` which is build+check.
#
# Plain docker and podman both work; the only bind mounts are read-only, which
# both engines handle the same way.
set -eu

: "${IMAGE:=bb}" "${TAG:=dev}" "${ENGINE:=podman}"
img="$IMAGE:$TAG"
here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH='' cd -- "$here/.." && pwd)"

say() {
	printf '\n== %s\n' "$1"
}

# Boots the image and pipes the script on stdin (--interactive is not optional:
# without it the engine gives bash empty stdin and bash -s exits 0 without
# running anything, a silent pass). TOKEN_ARGS is deliberately word-split into
# distinct --env flags; a GitHub token is [A-Za-z0-9_-]+, so none of its
# characters break that, and any other class of secret gets an explicit
# --env=value construction here.
crun() {
	# shellcheck disable=SC2086
	"$ENGINE" run --rm --interactive $TOKEN_ARGS "$@" "$img" /bin/bash -s
}

# mise resolves unpinned tools against the GitHub API (the first-use install
# below triggers that), so hand mise a token when one is available, exactly like
# `make build` does. The vars are only passed through when GH_TOKEN is set, so a
# tokenless check still works against a quiet IP.
TOKEN_ARGS=""
if [ -n "${GH_TOKEN:-}" ]; then
	# mise authenticates under MISE_GITHUB_TOKEN (the Containerfile does the same
	# export when mounting the build secret), so the value must arrive under that
	# name, not just GH_TOKEN.
	TOKEN_ARGS="--env GH_TOKEN --env MISE_GITHUB_TOKEN=$GH_TOKEN"
fi

# .dockerignore and .containerignore are two real files (a symlinked ignore file
# trades one failure mode for another: not every consumer follows it), so they
# need a sync assertion. .dockerignore carries an exact 2-line header, asserted
# verbatim below so it cannot silently become a pattern, then a body that has to
# equal .containerignore.
say "the two ignore files stay in step"
[ "$(head -1 .dockerignore)" = "# NOTE: keep in step with .containerignore (make check asserts it); only this" ] ||
	{
		echo ".dockerignore's first header line drifted" >&2
		exit 1
	}
[ "$(sed -n '2p' .dockerignore)" = "# 2-line header differs between the two files." ] ||
	{
		echo ".dockerignore's second header line drifted" >&2
		exit 1
	}
docker_tail="$(mktemp)"
trap 'rm -rf "$docker_tail"' EXIT
tail -n +3 .dockerignore >"$docker_tail"
if ! diff -u "$docker_tail" .containerignore >/dev/null; then
	echo ".dockerignore's body drifted from .containerignore; keep both in step" >&2
	exit 1
fi
rm -f "$docker_tail"
echo ".dockerignore and .containerignore agree"

# The repo's Containerfile and mise.toml have to agree on the node version; the
# duplication is what keeps a toolset edit from rebuilding the node and bb layers.
say "node version agrees between container/Containerfile and mise.toml"
node_arg="$(sed -n 's/^ARG NODE_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
node_toml="$(sed -n 's/^node = "\(.*\)"$/\1/p' "$root/mise.toml")"
[ "$node_arg" = "$node_toml" ] ||
	{
		echo "node mismatch: Containerfile says '$node_arg', mise.toml says '$node_toml'" >&2
		exit 1
	}
echo "node $node_arg, agreed on both sides"

# Every script in the repo is formatted and linted; catches a bad edit in
# fontconfig.sh or in here before the slower checks run.
say "scripts pass shfmt and shellcheck"
crun --volume "$root:/src:ro" <<'SH'
set -eu
cd /src
fmt="$(shfmt -d build container 2>&1)" || {
	echo "$fmt" >&2
	exit 1
}
shellcheck build/check.sh container/entrypoint.sh container/fontconfig.sh
echo "shfmt and shellcheck ok"
SH

# Baked versions must match the Containerfile's ARGs; the Containerfile only
# builds and does not assert anything, so this is the check that proves node, bb
# and playwright are exactly what the recipe says.
say "baked versions match the Containerfile (bb, node, playwright)"
bb_arg="$(sed -n 's/^ARG BB_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
pw_arg="$(sed -n 's/^ARG PLAYWRIGHT_VERSION=\(.*\)$/\1/p' "$root/container/Containerfile")"
crun --env BB_VERSION="$bb_arg" --env NODE_VERSION="$node_arg" --env PLAYWRIGHT_VERSION="$pw_arg" <<'SH'
set -eu
[ "$(bb --version)" = "$BB_VERSION" ] ||
	{ echo "bb version is $(bb --version), expected $BB_VERSION" >&2; exit 1; }
[ "$(node --version)" = "v$NODE_VERSION" ] ||
	{ echo "node version is $(node --version), expected v$NODE_VERSION" >&2; exit 1; }
[ "$(playwright --version 2>/dev/null | grep -oE 'Version [0-9.]+' | cut -d' ' -f2)" = "$PLAYWRIGHT_VERSION" ] ||
	{ echo "playwright $(playwright --version), expected $PLAYWRIGHT_VERSION" >&2; exit 1; }
echo "bb $BB_VERSION, node v$NODE_VERSION, playwright $PLAYWRIGHT_VERSION, all matching"
SH

# Debian's /etc/profile resets PATH, which drops the mise shims; the profile fix in
# the container image puts them back, and a login shell is exactly the thing that
# would have dropped them (a non-login shell inherits ENV PATH and would pass even
# if the profile script were deleted), so the assertion runs inside one.
say "login shell keeps the shims that /etc/profile would otherwise drop"
crun <<'SH'
set -eu
exec bash -lc 'command -v rg >/dev/null && echo "login shell resolves rg: $(command -v rg)"'
SH

say "baked tools all run"
crun <<'SH'
set -eu
for c in "rg --version" "jq --version" "fd --version" "shfmt --version" \
	"shellcheck --version" "tmux -V" "git-lfs --version"; do
	$c >/dev/null
	echo "ok: $c"
done
# vi/vim must be the wrapper scripts in /usr/local/bin, never shims; mise dispatches
# on the tool name in argv[0], so a shim reached as "vim" fails with "vim is not a
# valid shim".
if ls /opt/mise/shims | grep -qE '^(vi|vim)$'; then
	echo "unexpected vi/vim shim present" >&2
	exit 1
fi
vi --version | head -1
SH

say "fontconfig override: drift guard, single xdg cache directory, match parity"
"$here/../container/fontconfig.sh" check
# The runtime view: fc-cache must succeed, must report cache directories at all,
# and every directory it names must be the xdg one; an extra directory beside it is
# a wrong cachedir list, not a different spelling of success. LC_ALL=C keeps the
# grep independent of the image's or the caller's locale, and, following the line
# handling above, the "one allowed directory" is an exact comparison, not a lone
# grep for it. Chromium's launch smoke below covers whether the runtime honours
# FONTCONFIG_FILE; asserting the abscnce of the chmod is a syscall-level check
# that this harness deliberately does not do.
crun <<'SH'
set -eu
runtime_out="$(XDG_CACHE_HOME=/tmp/fc LC_ALL=C fc-cache -v 2>&1)"
cache_dirs="$(printf '%s\n' "$runtime_out" | grep -i 'cache directory' | sed 's/:.*//' | sort -u)"
[ -n "$cache_dirs" ] || { echo "fc-cache reported no cache directories" >&2; exit 1; }
[ "$cache_dirs" = "/tmp/fc/fontconfig" ] ||
	{
		echo "unexpected cache directory list; expected only /tmp/fc/fontconfig, got:" >&2
		echo "$cache_dirs" >&2
		exit 1
	}
for f in mono monospace serif sans-serif "sans serif" sans emoji; do
	s=$(FONTCONFIG_FILE=/etc/fonts/fonts.conf fc-match "$f")
	o=$(fc-match "$f")
	[ "$s" = "$o" ] || { echo "MISMATCH $f: stock=$s override=$o" >&2; exit 1; }
done
echo "fc-cache names one xdg cache directory; fc-match parity ok"
SH

say "Chromium launches twice, cold cache then warm"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/two.cjs" <<'EOF'
const { chromium } = require("playwright");
(async () => {
	for (let i = 1; i <= 2; i++) {
		const b = await chromium.launch();
		await b.close();
		console.log("launch " + i + " ok");
	}
})();
EOF
crun --volume "$tmp/two.cjs:/tmp/two.cjs:ro" <<'SH'
set -eu
NODE_PATH="$(npm root -g)" XDG_CACHE_HOME=/tmp/fcfc node /tmp/two.cjs
SH

say "first-use install of a lazy tool works"
crun <<'SH'
set -eu
go version
SH

# The invariant derived images depend on: the mise data dir is developer-owned and
# writable, so derived images can add tools and they stay usable. See README,
# "Using this image as a base".
say "mise data dir is writable by the image user; derived images depend on it"
crun --user developer <<'SH'
set -eu
test -w /opt/mise/installs
test -w /opt/mise/shims
for d in /opt/mise/installs/node/*/lib/node_modules; do
	[ -d "$d" ] || continue
	test -w "$d"
done
probe=/opt/mise/installs/.writable-probe
touch "$probe"
rm "$probe"
echo "writable by $(id -un)"
SH

say "build token does not appear anywhere in the image filesystem"
if [ -n "${GH_TOKEN:-}" ]; then
	# Three exit codes, so the scan fails closed on its own failures: 0 means
	# no match, 3 means a file matched (a leak, printed as hits), anything else
	# (grep read errors, a vanished subtree mid-scan) is a scan failure and
	# must fail the check rather than print "no matches". The token reaches
	# grep through stdin (-f -), so it never lands in an environment, on a
	# command line, or on disk. The scan cannot see bytes in a lower layer
	# that a later layer deleted, since that content is whiteouted rather than
	# removed; the sentinel procedure in AGENTS.md is the only check that
	# decompresses the layers themselves, and is the right tool for that blind
	# spot. Running as uid 0 (like the old build-time guard) shrinks the
	# unreadable-path blind spot to 0700 dirs; stderr's permission noise is
	# exactly why an unreadable path is an exit 2, not silence.
	leak_rc=0
	# The inner payload is deliberately single-quoted so the outer shell does not
	# expand the container-side script; expanding it would run $-substitutions
	# meant for the container. SC2016 flags exactly that pattern.
	# shellcheck disable=SC2016
	leak="$(printf '%s' "$GH_TOKEN" | "$ENGINE" run --rm --interactive --user 0 "$img" /bin/bash -c '
		set -eu
		tmp=$(mktemp -d)
		trap "rm -rf $tmp" EXIT
		rc=0
		grep -rlF --binary-files=text -f - / --exclude-dir=proc --exclude-dir=sys --exclude-dir=dev --exclude-dir=run 2>/dev/null >"$tmp/hits" || rc=$?
		case $rc in
			0|1) ;;
			*) echo "grep exited $rc (unreadable or errored subtree)" >&2; exit 2 ;;
		esac
		if [ -s "$tmp/hits" ]; then
			head -5 "$tmp/hits"
			exit 3
		fi
		echo no-leak
	')" || leak_rc=$?
	if [ "$leak_rc" -eq 3 ]; then
		echo "build token found on disk:" >&2
		echo "$leak" >&2
		exit 1
	fi
	[ "$leak_rc" -eq 0 ] ||
		{
			echo "token scan failed with status $leak_rc; that is a scan error, not a clean image" >&2
			exit 1
		}
	echo "no matches"
else
	echo "skipped, no GH_TOKEN supplied"
fi

# Nothing heavy may live in $HOME at first boot: it is volume-backed, and whatever
# is here gets copied in and frozen when the named volume is first created.
say "home stays small; build residue here gets frozen into the volume on first boot"
home_kb="$("$ENGINE" run --rm "$img" /bin/bash -c 'du -sk /home/developer' | cut -f1)"
echo "home is ${home_kb}K"
[ "$home_kb" -le 40 ] ||
	{
		echo "home grew past 40K (it should stay near 20K); look for build residue writing into \$HOME (see AGENTS.md)" >&2
		exit 1
	}

printf '\nall checks passed\n'
