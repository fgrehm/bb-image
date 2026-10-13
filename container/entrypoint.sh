#!/usr/bin/env bash
# Run bb and mirror its log files to the container's output.
#
# bb writes service output to files under its data dir and never to stdout, so
# without this the container's terminal is silent. Running bb in the background
# behind a single PID 1 lets that PID both follow the logs and forward SIGTERM,
# so `podman stop` shuts bb down cleanly (bb-app traps SIGTERM and exits 0)
# rather than killing it after the grace period.
#
# There is deliberately no `mise reshim` here. The shim farm lives at
# /opt/mise/shims, outside the home volume, so it is never shadowed by a stale
# copy of itself and never needs reconciling at startup.
set -uo pipefail

data_dir="${BB_DATA_DIR:-$HOME/.bb}"
log_dir="$data_dir/logs"
mkdir -p "$log_dir"

# Reconcile the home volume with what this image ships: a named volume is
# seeded exactly once, so without this an existing volume never picks up later
# image updates to AGENTS.md or the shell rc blocks. Copies a user edited are
# left untouched; a hydration problem is reported here but never fatal.
/usr/local/share/bb/hydrate-home.sh install

# -F follows by name and retries, so this is safe to start before bb has
# created either log.
tail -F -n 25 "$log_dir/server-stdio.log" "$log_dir/host-daemon-stdio.log" 2>/dev/null &
tail_pid=$!

# Default to serving bb. Callers can pass their own command instead.
if [ "$#" -eq 0 ]; then
	set -- bb-app \
		--server-bind-host "${BB_SERVER_BIND_HOST:-0.0.0.0}" \
		--server-port "${BB_SERVER_PORT:-38886}"
fi

"$@" &
bb_pid=$!

trap 'kill -TERM "$bb_pid" 2>/dev/null' TERM INT

# A trapped signal makes `wait` return early with a status above 128, before the
# child has actually exited. Keep waiting until bb is really gone so its own
# exit code is what the container reports.
status=0
while kill -0 "$bb_pid" 2>/dev/null; do
	wait "$bb_pid"
	status=$?
done

kill "$tail_pid" 2>/dev/null
wait "$tail_pid" 2>/dev/null

exit "$status"
