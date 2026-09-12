IMAGE ?= bb
TAG ?= dev
ENGINE ?= podman

# Read from the Containerfile so a release tag states the bb version without it
# having to be repeated on the command line.
BB_VERSION := $(shell sed -n 's/^ARG BB_VERSION=\(.*\)/\1/p' Containerfile)

# Host port for the bb server. Override when something else already owns 38886,
# e.g. `make run BB_PORT=39886`.
BB_PORT ?= 38886
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

# Extra flags, e.g. RUN_ARGS='-v ~/src:/home/developer/src:Z'
RUN_ARGS ?=

.PHONY: build hack run release

build:
	$(ENGINE) build -t $(IMAGE):$(TAG) .

hack:
	$(ENGINE) run --rm -it $(USERNS) $(VOLUMES) $(MOUNTS) $(RUN_ARGS) $(IMAGE):$(TAG) /bin/bash

# Serves bb with the entrypoint in front, so SIGTERM from `podman stop` reaches
# bb and it exits cleanly. Logs are tailed to the terminal by the entrypoint.
run:
	$(ENGINE) run --rm \
		--name $(NAME) \
		$(USERNS) \
		-p $(BB_PORT):38886 \
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
