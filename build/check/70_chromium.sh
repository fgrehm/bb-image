# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full full-sudo

# Chromium smoke: it must launch twice with a cold then warm fontconfig cache.
# The write-level gate (what a942844 exists for) lives in 71 of this directory.
say "Chromium launches twice, cold cache then warm"

# The staging dir is made readable and traversable by whatever uid the container
# lands on: without keep-id a container uid can be a host subuid, and a default
# 700 mktemp dir would be invisible to it. World-readable plus execute is
# enough for a read-only mount.
tmp="$(mktemp -d)"
chmod 755 "$tmp"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/two.cjs" <<'EOF'
const { chromium } = require("playwright");
(async () => {
	for (let i = 1; i <= 2; i++) {
		const b = await chromium.launch();
		const page = await b.newPage();
		await page.goto("data:text/html,<h1>ok</h1>");
		await page.screenshot({ path: "/tmp/two-" + i + ".png" });
		await b.close();
		console.log("launch " + i + " ok");
	}
})();
EOF
# The screenshot file is the proof navigation rendered, not just that the
# browser process started: it is checked for size after the run.
crun --volume "$tmp/two.cjs:/tmp/two.cjs:ro" <<'SH'
set -eu
NODE_PATH="$(npm root -g)" XDG_CACHE_HOME=/tmp/fcfc node /tmp/two.cjs
for i in 1 2; do
	[ -s "/tmp/two-$i.png" ] || {
		echo "screenshot $i missing or empty; Chromium launched but did not render" >&2
		exit 1
	}
done
SH
