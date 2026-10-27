# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full slim worker vm exedev worker-vm

# Debian's minimal base ships neither iproute2 nor net-tools. Both are in the
# foundation inventory so agents and the docs can name sockets the way modern
# runbooks do (`ss`, `ip`) and the way older ones do (`netstat`, `ifconfig`).
say "iproute2 and net-tools both answer for sockets and addresses"
crun <<'SH'
set -eu

ip -br addr >/dev/null
ip -o route >/dev/null
ss -ltn >/dev/null
netstat -ltn >/dev/null
ifconfig -a >/dev/null

echo "ip, ss, netstat and ifconfig are all present"
SH
