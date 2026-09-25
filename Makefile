IMAGE ?= bb
TAG ?= dev
ENGINE ?= podman

# Containerfile stage to build, passed as --target. Defaults to the flavor so
# that `make build FLAVOR=slim` builds what `make check FLAVOR=slim` checks.
# Empty builds the final release stage, the full image behind today's
# unsuffixed tags.
TARGET ?= $(FLAVOR)
FLAVOR ?= full

# Read from the Containerfile so a release tag states the bb version without it
# having to be repeated on the command line.
BB_VERSION := $(shell sed -n 's/^ARG BB_VERSION=\(.*\)/\1/p' container/Containerfile)

# Host port for the bb server. Override when something else already owns 38886,
# e.g. `make run BB_PORT=39886`.
BB_PORT ?= 38886

# Interface to publish bb on. Loopback by default, for two reasons: bb is a local
# single-user tool, and publishing on every interface breaks `localhost` here.
# A wildcard publish makes pasta listen dual-stack, IPv6 connections get reset, and
# `localhost` resolves to ::1 first, so clients fail instead of falling back to
# IPv4. Bound to 127.0.0.1 there is no IPv6 listener, so `localhost` works. Set
# BB_BIND=0.0.0.0 to expose bb on the LAN, and reach it by IPv4 address.
BB_BIND ?= 127.0.0.1
# Container name, so `podman stop bb` works and shutdown stays clean.
NAME ?= bb

# One volume, holding the whole home directory, so credentials, git config, ssh
# keys, shell history, and bb state all survive a container rebuild with no
# per-CLI mount list to maintain. It is seeded from the image the first time it
# is created, which is where ~/.bb and the shell config come from.
#
# The toolchain deliberately is not volume-backed. It lives in the image at
# /opt/mise so it stays in step with the image rather than freezing at volume
# creation, and so the first-boot copy into this volume stays small.
HOME_VOLUME ?= bb-home
VOLUMES = -v $(HOME_VOLUME):/home/developer

# Optional host integration, for reusing logins you already have instead of
# signing in again inside the container. See the README.
MOUNTS ?=

# Rootless podman maps container uid 1000 to a subordinate uid by default, so
# anything the container writes to a bind mount lands owned by a subuid and
# cannot be touched on the host. keep-id maps it back to your own uid, which is
# what makes mounting your code work. Override with USERNS= when using docker.
USERNS ?= --userns=keep-id

# Neutralises setuid and file capabilities inside the container, so nothing in the image
# can elevate. The base packages bring the standard Debian setuid set (su, mount, passwd,
# chsh, chfn, gpasswd, newgrp, umount, and openssh's ssh-keysign) and none of it serves
# this image's purpose, so agents should not be able to parlay it into container root.
# Bubblewrap is unaffected, because creating a user namespace is not a privilege gain.
#
# sudo flavors cannot take this flag: passwordless sudo is setuid and stops
# working under no-new-privileges. Both VM flavors need an unrestricted init
# workload, even though the standard vm flavor has no sudo. Choosing one of
# these flavors chooses the security posture, and the flag disappears with it.
# Override with SECURITY_OPTS= if you need su inside a standard profile.
ifneq (,$(filter %-sudo vm exedev,$(FLAVOR)))
SECURITY_OPTS ?=
else
SECURITY_OPTS ?= --security-opt no-new-privileges
endif

# Forward a GitHub token so mise's API calls are authenticated. Unauthenticated, mise
# gets 60 requests per hour against 1000 with a token, which is the difference between an
# intermittent attestation failure and a clean build.
#
# Lookup order: an explicit GH_TOKEN, then GITHUB_TOKEN, then whatever `gh auth token` has
# cached locally. The gh call is deferred, so it only happens when a build expands the
# flag, and its output goes into the environment rather than onto a command line.
#
# Exported so podman can read it from its own environment, and handed over as `type=env`,
# so the value never reaches a command line, make's echoed recipe, or the image. With no
# token the build runs unauthenticated, which is fine on a quiet IP and flaky elsewhere.
# Only `build` uses this; `run` and `hack` do not build.
GH_TOKEN ?= $(or $(GITHUB_TOKEN),$(shell gh auth token 2>/dev/null))
export GH_TOKEN
# The value holds commas, so it stays out of the $(if) call itself: make splits the
# then-branch on them otherwise, which silently truncates the flag.
GH_TOKEN_SECRET = --secret id=github_token,type=env,env=GH_TOKEN
BUILD_SECRET = $(if $(GH_TOKEN),$(GH_TOKEN_SECRET))

# Extra flags, e.g. RUN_ARGS='-v ~/src:/home/developer/src:Z'
RUN_ARGS ?=

.PHONY: build check ci check-smolvm-systemd fonts-regen hack run release

build:
	$(ENGINE) build -f container/Containerfile $(if $(TARGET),--target $(TARGET)) -t $(IMAGE):$(TAG) $(BUILD_SECRET) .

# All verification now lives here, run against the built image: behavioural
# checks (launch smoke, fontconfig override, first-use install, home size) in
# build/check.sh, and the guards that used to be RUNs at the tail of the
# Containerfile (fonts.conf drift, token leak, mise data-dir ownership). The
# publish workflow runs this before the push step, so a release cannot ship
# while anything here fails. Forwarded token works the same way it does for
# build: GH_TOKEN, then GITHUB_TOKEN, then `gh auth token`.
check:
	IMAGE=$(IMAGE) TAG=$(TAG) ENGINE=$(ENGINE) FLAVOR=$(FLAVOR) build/check.sh

# Build then verify, in one target: the sequence CI runs (its build and check
# steps are separate because buildx's GHA cache and the image attestations live
# in the build step, and the check must run against the self-same staged
# artifact), but spelled once so nobody drifts between building and checking.
# Use `make ci` locally; CI still splits only for the cache/attestation split.
ci: build
	IMAGE=$(IMAGE) TAG=$(TAG) ENGINE=$(ENGINE) FLAVOR=$(FLAVOR) build/check.sh

# Host-only boot gate for the systemd VM target. This requires smolvm and
# KVM/libkrun, so it is deliberately separate from the container-safe checks.
check-smolvm-systemd:
	IMAGE=$(IMAGE) TAG=$(TAG) ENGINE=$(ENGINE) FLAVOR=$(FLAVOR) build/check-smolvm-systemd.sh

# Regenerates container/fonts.conf from the distro fontconfig inside the image;
# the thing to do after a font package bump moves /etc/fonts/fonts.conf. The
# result is validated with the drift guard before it replaces the file.
fonts-regen:
	IMAGE=$(IMAGE) TAG=$(TAG) ENGINE=$(ENGINE) container/fontconfig.sh regen

hack:
	$(ENGINE) run --rm -it $(USERNS) $(SECURITY_OPTS) $(VOLUMES) $(MOUNTS) $(RUN_ARGS) $(IMAGE):$(TAG) /bin/bash

# Serves bb with the entrypoint in front, so SIGTERM from `podman stop` reaches
# bb and it exits cleanly. Logs are tailed to the terminal by the entrypoint.
run:
	$(ENGINE) run --rm \
		--name $(NAME) \
		$(USERNS) \
		$(SECURITY_OPTS) \
		-p $(BB_BIND):$(BB_PORT):38886 \
		$(VOLUMES) \
		$(MOUNTS) \
		$(RUN_ARGS) \
		$(IMAGE):$(TAG)

# Tags the image's own version and pushes it, which is what triggers the publish
# workflow. The tag carries the bb version in its message so `git tag -n` answers
# "which bb is in this one" without opening the Containerfile. A version with a
# prerelease suffix, such as 0.3.0-rc1, publishes an img- tag only and does not
# move the bb aliases or latest.
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.2.0" >&2; exit 1; }
	@test -z "$$(git status --porcelain)" || { echo "working tree is dirty" >&2; exit 1; }
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then \
		echo "tag v$(VERSION) already exists" >&2; exit 1; \
	fi
	git tag -a "v$(VERSION)" -m "image $(VERSION), bb $(BB_VERSION)"
	git push origin "v$(VERSION)"
	@echo "pushed v$(VERSION) (bb $(BB_VERSION)); watch it at https://github.com/fgrehm/bb-image/actions"
