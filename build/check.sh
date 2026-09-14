#!/bin/sh
# Behavioural checks against a built image. The Containerfile carries no
# verification RUNs; every assertion lives here, and the publish workflow runs this
# script before an image is pushed, so a release cannot ship while anything here
# fails. Run it by hand as `make check`.
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
# distinct --env flags.
crun() {
	# shellcheck disable=SC2086
	"$ENGINE" run --rm --interactive $TOKEN_ARGS "$@" "$img" /bin/bash -s
}

# mise resolves unpinned tools against the GitHub API (the first-use install below
# triggers that), so hand mise a token when one is available, exactly like
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
# need a sync assertion; the only permitted difference is .dockerignore's header
# note, which this comparison skips by ignoring the first three lines.
say "the two ignore files stay in step"
docker_tail="$(mktemp)"
trap 'rm -rf "$docker_tail"' EXIT
tail -n +3 .dockerignore >"$docker_tail"
if ! diff -u "$docker_tail" .containerignore >/dev/null; then
	echo ".dockerignore drifted from .containerignore; keep both in step" >&2
	exit 1
fi
rm -f "$docker_tail"
trap - EXIT
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

# Debian's /etc/profile resets PATH, which drops the mise shims; the profile fix in
# the container image puts them back, and this verifies that it did.
say "login shell keeps the shims that /etc/profile would otherwise drop"
crun <<'SH'
set -eu
command -v rg
echo "rg resolves: $(command -v rg)"
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
# The runtime view: fc-cache must see exactly the xdg cache, and fc-match has to
# agree with the distro file family for family, including the mono alias, which
# lives inline in fonts.conf and nowhere in conf.d. LC_ALL=C on the fc-cache grep
# keeps the assertion independent of the locale the image or the caller carries.
crun <<'SH'
set -eu
XDG_CACHE_HOME=/tmp/fc LC_ALL=C fc-cache -v 2>&1 | grep -i 'cache directory'
for f in mono monospace serif sans-serif "sans serif" sans emoji; do
	s=$(FONTCONFIG_FILE=/etc/fonts/fonts.conf fc-match "$f")
	o=$(fc-match "$f")
	[ "$s" = "$o" ] || { echo "MISMATCH $f: stock=$s override=$o" >&2; exit 1; }
done
echo "fc-match parity ok"
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
	# The token reaches grep through stdin (-f -), so it never lands in an
	# environment, on a command line, or on disk. The scan cannot see bytes in a
	# lower layer that a later layer deleted, since that content is whiteouted
	# rather than removed; the sentinel procedure in AGENTS.md is the only check
	# that decompresses the layers themselves, and it is the right tool for the
	# blind spot here: unreadable paths inside the image. Running as uid 0
	# shrinks that blind spot to what 0700 root-owned dirs hide, rather than
	# the whole /root tree; 2>/dev/null keeps permission noise off the log
	# instead of pretending it was scanned.
	leak="$(printf '%s' "$GH_TOKEN" | "$ENGINE" run --rm --interactive --user 0 "$img" /bin/bash -c \
		'grep -rlF --binary-files=text -f - / --exclude-dir=proc --exclude-dir=sys --exclude-dir=dev --exclude-dir=run 2>/dev/null | head -5')"
	if [ -n "$leak" ]; then
		echo "build token found on disk:" >&2
		echo "$leak" >&2
		exit 1
	fi
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
