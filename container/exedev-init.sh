#!/bin/sh
# exe.dev's image runtime invokes this as PID 1. Prepare the small amount of
# kernel state systemd expects before handing over to the real init.
set -eu

if [ "$$" -ne 1 ]; then
	echo "exedev-init must run as PID 1" >&2
	exit 1
fi

mkdir -p /run/systemd
if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
	mount -t cgroup2 none /sys/fs/cgroup
fi

exec /sbin/init --log-target=syslog --show-status=true
