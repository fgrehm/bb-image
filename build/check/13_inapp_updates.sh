#!/bin/sh
# shellcheck shell=sh disable=SC2148,SC2154
# check-scope: repo

say "in-app updates are enabled only for default bb starts"
for source in container/entrypoint.sh container/bb.service container/exedev-bb.service; do
	grep -Fq -- '--in-app-updates' "$root/$source" || {
		echo "$source does not enable bb in-app updates" >&2
		exit 1
	}
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Keep this a behavioral test of the actual entrypoint while making its image-
# absolute hydration helper a no-op outside a container.
sed 's#^/usr/local/share/bb/hydrate-home.sh install$#:#' \
	"$root/container/entrypoint.sh" >"$tmp/entrypoint.sh"
cat >"$tmp/mock-command" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$ARGS_FILE"
SH
chmod 0755 "$tmp/mock-command"
ln -s mock-command "$tmp/bb-app"
ln -s mock-command "$tmp/caller-command"

mkdir -p "$tmp/home"
PATH="$tmp:$PATH" HOME="$tmp/home" ARGS_FILE="$tmp/default.args" \
	bash "$tmp/entrypoint.sh"
printf '%s\n' \
	--in-app-updates \
	--server-bind-host \
	0.0.0.0 \
	--server-port \
	38886 >"$tmp/expected-default.args"
cmp -s "$tmp/expected-default.args" "$tmp/default.args" || {
	echo "entrypoint default command is missing the in-app update flag or changed its defaults" >&2
	exit 1
}

PATH="$tmp:$PATH" HOME="$tmp/home" ARGS_FILE="$tmp/caller.args" \
	bash "$tmp/entrypoint.sh" caller-command caller-argument
printf '%s\n' caller-argument >"$tmp/expected-caller.args"
cmp -s "$tmp/expected-caller.args" "$tmp/caller.args" || {
	echo "entrypoint modified a caller-supplied command" >&2
	exit 1
}

echo "default starts enable updates; caller commands stay untouched"
