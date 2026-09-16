# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# Partials sourced by build/check.sh via build/check/lib.sh: IMAGE/TAG/ENGINE,
# img, root and the say/crun helpers come from there.
# check-flavors: full

# The gate a942844 exists for, asserted at syscall level via build/fcshim.c: an
# interposer over chmod/unlink/openat that logs every fontconfig-related path
# Chromium touches. A plain launch smoke cannot tell "nothing needed a write"
# from "writes happened and were hidden", so these assertions are about what
# the browser actually did:
#
#   - no fontconfig-related chmod calls outside the xdg cache. fontconfig does
#     chmod its own freshly-created cache directory too, which a sandbox permits,
#     but a chmod on the system fontconfig cache repeats the original prompt.
#   - the cold launch's only other records are the .uuid unlinks beside the
#     system font directories, the cold-cache class documented in CHANGELOG
#     (nothing creates those markers, so every cold cache unlinks each one).
#   - the warm launch records nothing. A missing or empty launch2.log is the
#     expected case: the shim creates the log lazily, on the first call worth
#     logging, and a warm cache has none.
#   - launch 1 must log at least one .uuid unlink, which proves the shim saw a
#     genuinely cold cache; a warm-cache run would make every assertion above
#     a vacuous pass.
say "Chromium fontconfig writes stay inside the xdg cache (fcshim, syscall level)"
tmp="$(mktemp -d)"
chmod 755 "$tmp"
trap 'rm -rf "$tmp"' EXIT
cp "$root/build/fcshim.c" "$tmp/"
cat >"$tmp/one.cjs" <<'EOF'
const { chromium } = require("playwright");
chromium
	.launch()
	.then(async (b) => {
		await b.close();
		console.log("launch ok");
	})
	.catch((e) => {
		console.error(e);
		process.exit(1);
	});
EOF
# one.cjs is copied to /tmp inside the container, where node runs; /artifact is
# the read-only staging mount.
crun --volume "$tmp:/artifact:ro" <<'SH'
set -eu
cp /artifact/one.cjs /tmp/one.cjs
gcc -shared -fPIC -O2 -o /tmp/fcshim.so /artifact/fcshim.c -ldl

# Prove each wrapper used by the gate is loaded, including resolution of paths
# passed relative to a directory fd. Call the libc symbols directly from a tiny
# C probe; language runtimes may bypass them or choose related *at variants.
cat >/tmp/fcshim-probe.c <<'C'
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
  const char *dir = "/tmp/fcshim-probe/fontconfig";
  if (mkdir("/tmp/fcshim-probe", 0755) != 0) return 1;
  if (mkdir(dir, 0755) != 0) return 2;
  if (chmod(dir, 0755) != 0) return 3;
  int dirfd = open(dir, O_RDONLY);
  if (dirfd < 0) return 4;
  int fd = openat(dirfd, "probe", O_WRONLY | O_CREAT, 0600);
  if (fd < 0) return 5;
  if (close(fd) != 0) return 6;
  if (unlinkat(dirfd, "probe", 0) != 0) return 7;
  if (close(dirfd) != 0) return 8;
  (void)unlink("/tmp/fcshim-probe/.uuid");
  return 0;
}
C
gcc -O0 -fno-builtin -o /tmp/fcshim-probe-bin /tmp/fcshim-probe.c
probe_rc=0
FCLOG=/tmp/probe.log LD_PRELOAD=/tmp/fcshim.so /tmp/fcshim-probe-bin || probe_rc=$?
[ "$probe_rc" -eq 0 ] || {
	echo "fcshim probe executable failed with status $probe_rc" >&2
	cat /tmp/probe.log 2>/dev/null >&2 || true
	exit 1
}
probe_has() {
	grep -qFx "$1" /tmp/probe.log || {
		echo "fcshim probe did not record: $1" >&2
		cat /tmp/probe.log >&2
		exit 1
	}
}
probe_has 'chmod /tmp/fcshim-probe/fontconfig'
probe_has 'openat(O_CREAT) /tmp/fcshim-probe/fontconfig/probe'
probe_has 'unlinkat /tmp/fcshim-probe/fontconfig/probe'
probe_has 'unlink /tmp/fcshim-probe/.uuid'

NODE_PATH="$(npm root -g)" XDG_CACHE_HOME=/tmp/fcfc \
	FCLOG=/tmp/launch1.log LD_PRELOAD=/tmp/fcshim.so node /tmp/one.cjs
NODE_PATH="$(npm root -g)" XDG_CACHE_HOME=/tmp/fcfc \
	FCLOG=/tmp/launch2.log LD_PRELOAD=/tmp/fcshim.so node /tmp/one.cjs

uuids="$(grep -c '^unlink .*\.uuid' /tmp/launch1.log || true)"
[ "$uuids" -ge 1 ] ||
	{
		echo "cold launch recorded no .uuid unlink; the shim saw a warm cache, so these assertions would be vacuous" >&2
		exit 1
	}

# Every call the cold launch made must be either the accepted .uuid unlink
# beside a system font directory, or fontconfig's own bookkeeping inside its
# allotted cache (the chmod of its fresh dir, and the temp/LCK unlink churn of
# an atomic cache rebuild). Anything else means a sandboxed agent gets a
# prompt the cache change cannot explain, and that fails the release.
bad="$(grep -h -v -E '^unlink(at)? /usr/share/fonts(/.*)?\.uuid$|^unlink(at)? /usr/local/share/fonts(/.*)?\.uuid$|^chmod /tmp/fcfc/|^unlink(at)? /tmp/fcfc/|^openat\(O_CREAT\) /tmp/fcfc/' /tmp/launch1.log /tmp/launch2.log 2>/dev/null || true)"
if [ -n "$bad" ]; then
	echo "unexpected fontconfig-related writes outside the accepted classes:" >&2
	echo "$bad" >&2
	exit 1
fi
echo "cold launch: $uuids .uuid unlinks (accepted class); warm launch: nothing"
SH
