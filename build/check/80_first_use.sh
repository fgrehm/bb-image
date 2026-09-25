# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# shellcheck source=build/check/lib.sh
# check-flavors: full full-sudo exedev

# First-use installs are the most likely regression: a lazy tool resolves on its
# first invocation, talks to the GitHub release API, and installs into the home
# volume. go is small and exercises the whole path.
say "first-use install of a lazy tool works"
# crun is offline by default so baked-tool checks never refresh every unpinned
# lazy tool. This concern exists to exercise the network install path.
crun --env MISE_OFFLINE=0 <<'SH'
set -eu
go version
SH
