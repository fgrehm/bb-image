#!/bin/sh
# Shared environment and helpers for the make check runner. Sourced by
# build/check.sh before any check fragment runs, so every fragment sees exactly
# the same IMAGE, TAG, ENGINE, GH_TOKEN forwarding and container runner.
set -eu

: "${IMAGE:=bb}" "${TAG:=dev}" "${ENGINE:=podman}"
img="$IMAGE:$TAG"
TOKEN_ARGS=
# root is defined by the runner; fragments use it.

say() {
	printf '\n== %s\n' "$1"
}

# Boots the image and pipes the script on stdin (--interactive is not optional:
# without it the engine gives bash empty stdin and bash -s exits 0 without
# running anything, a silent pass). Checks use already-installed tools unless a
# fragment explicitly opts back online, which stops every shim invocation from
# refreshing the unpinned lazy tools. TOKEN_ARGS is deliberately word-split into
# distinct --env flags; a GitHub token is [A-Za-z0-9_-]+, so no value needs
# quoting, and any odd class must be passed as --env NAME=value here.
crun() {
	# shellcheck disable=SC2086
	"$ENGINE" run --rm --interactive $TOKEN_ARGS --env MISE_OFFLINE=1 --env MISE_QUIET=1 "$@" "$img" /bin/bash -s
}

if [ -n "${GH_TOKEN:-}" ]; then
	# mise authenticates under MISE_GITHUB_TOKEN (the Containerfile does the
	# same export when mounting the build secret), so the value must arrive
	# under that name, not just GH_TOKEN.
	TOKEN_ARGS="--env GH_TOKEN --env MISE_GITHUB_TOKEN=$GH_TOKEN"
fi
