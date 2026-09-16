# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim slim-sudo full-sudo

# The container-level AGENTS.md bb appends to every provider-backed thread and
# the mise activation blocks in the shell rc files are home-volume content, and
# a named volume is seeded from the image exactly once. Rather than freezing,
# they are hydrated on every container start by hydrate-home.sh against a
# registry shipped outside the volume. This fragment asserts both the shipped
# state and the mechanism itself: fresh installs, our stale copies updated, and
# user-edited copies left alone. The guidance is one source for every flavor,
# deliberately: it keeps a hash chain shared across a container that moved from
# full to slim (or back) so hydration replaces the image's own wording instead
# of preserving either copy or feeding newly particular guidance.
say "AGENTS.md shipped with the mise guidance; registry stamped; home hydrated at build"
crun --user developer <<'SH'
set -eu
share=/usr/local/share/bb
for f in agents.md managed.tsv managed-prev.tsv hydrate-home.sh rc-bash.sh rc-zsh.sh; do
	test -f "$share/$f"
done
for phrase in \
	'managed by mise' \
	'mise use <tool>@<version>' \
	'mise trust' \
	'/opt/mise' \
	'mise reshim' \
	'What is baked varies by image flavor'; do
	grep -qF "$phrase" "$share/agents.md" ||
		{ echo "AGENTS.md is missing expected content: $phrase" >&2; exit 1; }
done
# Every registry row carries the hash of its source: stamp ran at build.
while IFS="$(printf '\t')" read -r target mode source hash; do
	[ -n "$target" ] || continue
	case $target in '#'*) continue ;; esac
	[ -n "$hash" ] ||
		{ echo "registry row for $target is unstamped" >&2; exit 1; }
	[ "$(sha256sum "$share/$source" | cut -d' ' -f1)" = "$hash" ] ||
		{ echo "registry hash for $target does not match $source" >&2; exit 1; }
done <"$share/managed.tsv"
# The build-time hydration populated the image's home.
grep -qF 'managed by mise' /home/developer/.bb/AGENTS.md
grep -qxF '# bb-image managed >>>' /home/developer/.bashrc
grep -qxF 'eval "$(mise activate bash)"' /home/developer/.bashrc
grep -qxF 'eval "$(mise activate zsh)"' /home/developer/.zshrc
echo "shipped state ok"
SH

say "hydration: fresh install, user edits preserved, stale copies replaced"
crun --user developer <<'SH'
set -eu
agents_source=agents.md
run_install() { HOME="$home" BB_MANAGED_SHARE="$share" bash "$share/hydrate-home.sh" install >/dev/null; }
share=/tmp/hydrate-share
home=/tmp/hydrate-home
rm -rf "$share" "$home"
mkdir -p "$share" "$home/.bb"
cp /usr/local/share/bb/managed.tsv /usr/local/share/bb/hydrate-home.sh "$share/"

# Synthetic sources, so the test stays independent of the shipped content.
printf 'agents v1\n' >"$share/$agents_source"
printf '# snippet v1\n' >"$share/rc-bash.sh"
printf '.bb/AGENTS.md\tfile\t%s\n.bashrc\tblock\trc-bash.sh\n' "$agents_source" >"$share/managed.tsv"
: >"$share/managed-prev.tsv"
BB_MANAGED_SHARE="$share" bash "$share/hydrate-home.sh" stamp

# 1. Fresh home: both targets appear with the shipped content.
run_install
grep -q 'agents v1' "$home/.bb/AGENTS.md"
grep -q 'snippet v1' "$home/.bashrc"
grep -qxF '# bb-image managed >>>' "$home/.bashrc"

# 2. A user edit survives a later install: outside the block in the rc file
#    and inside it, where the whole block stops being ours.
printf 'user tail\n' >>"$home/.bb/AGENTS.md"
printf '# bb-image managed >>>\n# snippet v1\neval extra=true\n# bb-image managed <<<\nalias mything=true\n' >"$home/.bashrc"
run_install
grep -q 'user tail' "$home/.bb/AGENTS.md" ||
	{ echo "user-edited AGENTS.md was overwritten" >&2; exit 1; }
grep -q 'alias mything=true' "$home/.bashrc" ||
	{ echo "user shell config was overwritten" >&2; exit 1; }
grep -q 'eval extra' "$home/.bashrc" ||
	{ echo "user-edited block was overwritten" >&2; exit 1; }

# 3. An unmodified stale copy is replaced once the image moves on, the way a
#    bump replaces our own shipped version. Recording the old hash in
#    managed-prev.tsv is what the maintainer does in the changing commit.
cp "$share/$agents_source" /tmp/v1-agents
cp "$share/rc-bash.sh" /tmp/v1-rc
printf 'agents v2\n' >"$share/$agents_source"
printf '# snippet v2\n' >"$share/rc-bash.sh"
printf '.bb/AGENTS.md\t%s\n.bashrc\t%s\n' \
	"$(sha256sum /tmp/v1-agents | cut -d' ' -f1)" \
	"$(sha256sum /tmp/v1-rc | cut -d' ' -f1)" >>"$share/managed-prev.tsv"
BB_MANAGED_SHARE="$share" bash "$share/hydrate-home.sh" stamp >/dev/null
# The stale copies are restored to exactly what a real shipped copy would be,
# without the user tails of step 2, and with content outside the managed block
# to prove a block update does not replace the whole rc file.
cp /tmp/v1-agents "$home/.bb/AGENTS.md"
{
	printf '%s\n' 'alias before=true' '# bb-image managed >>>'
	cat /tmp/v1-rc
	printf '%s\n' '# bb-image managed <<<' 'alias after=true'
} >"$home/.bashrc"
run_install
grep -q 'agents v2' "$home/.bb/AGENTS.md" ||
	{ echo "stale AGENTS.md was not updated" >&2; exit 1; }
grep -q 'snippet v2' "$home/.bashrc" ||
	{ echo "stale rc block was not updated" >&2; exit 1; }
grep -q 'snippet v1' "$home/.bashrc" &&
	{ echo "old rc block content survived the update" >&2; exit 1; }
grep -qxF 'alias before=true' "$home/.bashrc" &&
	grep -qxF 'alias after=true' "$home/.bashrc" ||
	{ echo "content outside the stale rc block was not preserved" >&2; exit 1; }

# 4. A repeated install is a no-op: byte-identical files, nothing rewritten.
cp "$home/.bb/AGENTS.md" /tmp/idempotent-agents
cp "$home/.bashrc" /tmp/idempotent-bashrc
run_install
cmp -s /tmp/idempotent-agents "$home/.bb/AGENTS.md" ||
	{ echo "repeated install modified AGENTS.md" >&2; exit 1; }
cmp -s /tmp/idempotent-bashrc "$home/.bashrc" ||
	{ echo "repeated install modified .bashrc" >&2; exit 1; }
echo "hydration behaviour ok"
SH
