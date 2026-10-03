#!/bin/sh
# Build the requested flavor and its internal parent images in dependency order.
set -eu

flavor=${FLAVOR:-full}
engine=${ENGINE:-podman}
image=${IMAGE:-bb}
tag=${TAG:-dev}
pins=container/Containerfile.foundation

# The foundation Containerfile is the single home for the version and build ARGs.
set --
while IFS= read -r line; do
	case "$line" in
	ARG\ *=*) set -- "$@" --build-arg "${line#ARG }" ;;
	esac
done <"$pins"

stages="$(sh build/manifest.sh stages "$flavor")"

if [ -n "${GH_TOKEN:-}" ]; then
	set -- "$@" --secret id=github_token,type=env,env=GH_TOKEN
fi

parent=
for stage in $stages; do
	if [ "$stage" = "$flavor" ]; then
		output="${image}:${tag}"
	else
		output="localhost/${image}-stage-${stage}:${tag}"
	fi
	if [ -n "$parent" ]; then
		"$engine" build -f "container/Containerfile.$stage" -t "$output" "$@" \
			--build-arg "BASE_IMAGE=localhost/${image}-stage-${parent}:${tag}" .
	else
		"$engine" build -f "container/Containerfile.$stage" -t "$output" "$@" .
	fi
	parent=$stage
done
