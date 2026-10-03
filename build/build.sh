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

case "$flavor" in
slim | worker) stages="foundation $flavor" ;;
full) stages='foundation worker full' ;;
slim-sudo) stages='foundation slim slim-sudo' ;;
full-sudo | vm) stages="foundation worker full $flavor" ;;
vm-sudo | exedev) stages="foundation worker full vm $flavor" ;;
worker-vm) stages='foundation worker worker-vm' ;;
*)
	echo "unknown flavor: $flavor" >&2
	exit 1
	;;
esac

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
