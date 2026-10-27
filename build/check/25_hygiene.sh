# Partials sourced by build/check.sh via build/check/lib.sh; IMAGE/TAG/ENGINE,
# img, root and say/crun come from there (SC2148/SC2153/SC2154 handled here).
# shellcheck shell=sh disable=SC2154,SC2148
# A repository check: the tree and its history are the same in every matrix job,
# so it runs once, in the full job (see build/check.sh), instead of three times.
# check-scope: repo

# gitleaks scans this repo, past and present: the git history, then the working
# tree as it stands (including uncommitted files). gitleaks is baked into the
# full flavor's toolset so this scan runs offline like the lint pass, and the
# release can never ship a tree that carries a secret. This is repo-side only;
# the token scan in 95_image_hygiene is its counterpart on the built image's
# filesystem, where the forwarded build token is the one input that must be
# absent.
say "the repo tree and its full history carry no leaked secrets"
# Git refuses a repository owned by another uid ('dubious ownership'), which is
# exactly a Docker bind mount into this container on a CI runner, where the
# repo owner's uid is not the container uid. The config is passed as
# environment variables rather than written to /etc, so nothing of the scan
# writes anywhere.
crun --volume "$root:/src:ro" <<'SH'
set -eu
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0=/src
gitleaks git --no-banner /src
gitleaks dir --no-banner /src
echo "no leaks in history or tree"
SH

# Lints every script in the repo, by the baked shfmt and shellcheck inside the
# image itself; catches a bad edit in fontconfig.sh or in here before the
# slower checks run.
say "scripts pass shfmt and shellcheck"
crun --volume "$root:/src:ro" <<'SH'
set -eu
cd /src
fmt="$(shfmt -d build container 2>&1)" || {
	echo "$fmt" >&2
	exit 1
}
shellcheck build/build.sh build/check.sh build/check-smolvm-systemd.sh build/check-smolvm-podman.sh \
	build/check/*.sh container/entrypoint.sh \
	container/fontconfig.sh container/hydrate-home.sh container/bb-backup
echo "shfmt and shellcheck ok"
SH
