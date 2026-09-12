# Pinned to the multi-arch OCI index digest for reproducible builds.
# Bump with: podman images --digests | grep debian
FROM docker.io/library/debian@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

# Scoped to the build rather than ENV, so it does not leak into the final image.
ARG DEBIAN_FRONTEND=noninteractive

# Only what mise has no backend for, plus python3, which matters here and basically
# nowhere else. During the bb install below, the global config still declares node
# alone, so no lazy shims exist yet and python3 is otherwise absent from the build.
# That is the blocker the README names for arm64 node-gyp builds. At runtime the
# mise shim sits ahead of /usr/bin on PATH, so bare python3 is mise's and this copy
# is reached by absolute path only.
#
# The rest are the gaps an agent host feels immediately: procps is `ps`, less is
# git's pager, unzip is assumed by installers, pkg-config is needed by native builds
# that build-essential does not cover, and gnupg is commit signing.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
                       build-essential \
                       ca-certificates \
                       curl \
                       git \
                       gnupg \
                       less \
                       libpq-dev \
                       libsqlite3-dev \
                       libssl-dev \
                       openssh-client \
                       pkg-config \
                       postgresql-client \
                       procps \
                       python3 \
                       rsync \
                       sqlite3 \
                       unzip \
                       wget \
                       zlib1g-dev \
                       zsh \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME

# ---------------------------------------------------------------------------
# mise, its toolchains, and the toolset all live outside the user's home.
#
# Home is volume-backed at runtime, and a named volume is seeded from the image
# exactly once. Anything the image owns under home would therefore freeze at
# first boot and shadow later image updates. Keeping the toolchain out of home
# means the baked tools stay in step with the image instead of drifting inside
# a volume, and it keeps the first-boot copy into that volume small.
# ---------------------------------------------------------------------------

# The installer verifies the release checksum. Pinning MISE_VERSION keeps the
# build reproducible and selects the checksum from that release's SHASUMS256.txt.
ARG MISE_VERSION=2026.9.5
RUN curl -fsSL https://mise.run \
    | MISE_INSTALL_PATH=/usr/local/bin/mise MISE_VERSION="v${MISE_VERSION}" sh

# MISE_DATA_DIR holds installed toolchains and the shim farm, and
# MISE_GLOBAL_CONFIG_FILE points the toolset outside home. Both are deliberately
# not volume-backed: what the image bakes stays current, and anything installed at
# runtime is per-container. /usr/local/bin, where the binary went, is on the
# default PATH.
#
# The toolset has to be the *global* config rather than the system config at
# /etc/mise, even though the latter reads just as well. mise only creates
# bootstrap shims for tools it picks up from the user or project scope, so the
# same file under /etc/mise yields shims for installed tools only: node and bb
# get one, every lazy tool silently does not, and first-use installation stops
# working because there is no shim to invoke. It is writable by the user so
# `mise use -g` works, though such changes live and die with the container.
ENV MISE_DATA_DIR=/opt/mise
ENV MISE_CACHE_DIR=/opt/mise/cache
ENV MISE_GLOBAL_CONFIG_FILE=/opt/mise/config.toml
ENV PATH="/opt/mise/shims:$PATH"

# npm's cache also lives outside home. It reached 100MB from the global installs
# below, and anything left in home is copied into the volume on first boot for no
# reason. Redirecting it here means no npm step can put it back.
ENV npm_config_cache=/opt/npm-cache

# node is the runtime the image is built around, so it is installed from an
# explicit version rather than read out of mise.toml. That means the version is
# named twice, here and in mise.toml, because a layer cannot both install node
# and depend on the file that declares it. The check further down fails the build
# if the two drift apart. This is a bootstrap config holding only node; the real
# toolset is copied in further down, after the expensive layers, so editing it
# does not invalidate them.
ARG NODE_VERSION=24.21.0
RUN mkdir -p /opt/mise /opt/npm-cache \
    && printf '[tools]\nnode = "%s"\n' "${NODE_VERSION}" > /opt/mise/config.toml \
    && chown -R $USERNAME:$USERNAME /opt/mise /opt/npm-cache

USER $USERNAME

# bb hosts many projects and resolves them by path, so home is the sane default
# rather than a single mount point. Mount a tree under it (see the Makefile).
WORKDIR /home/${USERNAME}

# node is the runtime the image is built around, so it is installed from an
# explicit version rather than read out of mise.toml. That means the version is
# named twice, here and in mise.toml, because a layer cannot both install node
# and depend on the file that declares it. The check further down fails the
# build if the two drift apart.
RUN mise install \
    && mise reshim --force \
    && node --version

# bb is installed globally into mise's node install, so bumping the node version
# above means reinstalling it. npm gates native-addon install scripts, so the
# three bb depends on have to be allowed explicitly or bb will not work:
# @parcel/watcher, better-sqlite3, and node-pty are compiled or fetched here.
ARG BB_VERSION=0.43.1
RUN npm install -g \
        --allow-scripts=@parcel/watcher,better-sqlite3,node-pty \
        "bb-app@${BB_VERSION}" \
    && mise reshim --force \
    && bb --version

# Playwright's Chromium, ready to use without a first-run download. Browsers go to
# /opt/ms-playwright, outside home, for the same reason as the toolchain: a
# volume-backed home would otherwise copy ~170MB into the volume at first boot.
#
# It is an npm global rather than a mise tool so that the browser download sits in
# a layer toolset edits do not invalidate, and because `install --with-deps` needs
# root, which the toolset layers deliberately are not.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
ARG PLAYWRIGHT_VERSION=1.63.0
RUN npm install -g "playwright@${PLAYWRIGHT_VERSION}" \
    && mise reshim --force \
    && playwright --version

USER root
RUN playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/* \
    && chown -R $USERNAME:$USERNAME /opt/ms-playwright
USER $USERNAME

# ~/.bb holds server state. It is created in the image so the copy-up into a home
# volume carries the right uid/gid: a volume created empty would be root-owned
# and bb could not write to it.
RUN mkdir -p /home/${USERNAME}/.bb

# Interactive shells get full activation for env vars and hooks. Shims stay on
# PATH for non-interactive processes. Home is volume-backed at runtime, so these
# files freeze at first boot and changing them later will not reach an existing
# volume.
RUN printf '%s\n' 'eval "$(mise activate bash)"' >> /home/${USERNAME}/.bashrc \
    && printf '%s\n' 'eval "$(mise activate zsh)"' >> /home/${USERNAME}/.zshrc

COPY --chown=$USERNAME:$USERNAME scripts/entrypoint.sh /home/${USERNAME}/entrypoint.sh

# ---------------------------------------------------------------------------
# The toolset. Only this and below rebuild when mise.toml changes.
# ---------------------------------------------------------------------------

# Overwrites the bootstrap config written above. Owned by the user so that
# `mise use -g` keeps working.
COPY --chown=$USERNAME:$USERNAME mise.toml /opt/mise/config.toml

# Catch a NODE_VERSION that no longer matches the toolset rather than shipping an
# image whose node is not the one mise reports. Then install the baked tools and
# reconcile the shim farm. This is the layer that downloads the baked dev tools
# (rg, jq, nvim and friends), so a toolset edit re-downloads them. node, bb and
# Playwright's Chromium sit above it and stay cached.
#
# The rm at the end is load-bearing, and it has to be last in the RUN. Installing
# the aqua-backed tools leaves mise's sigstore TUF cache in ~/.cache/sigstore-rust
# and its state in ~/.local/state/mise: MISE_CACHE_DIR does not cover the former,
# which follows XDG_CACHE_HOME. Every later command in this RUN goes through a mise
# shim and recreates the state dir, so anything after the rm puts it back. Home is
# volume-backed and seeded once, so leftovers here bake into every new volume.
# Setting MISE_STATE_DIR and XDG_CACHE_HOME is the alternative, at the cost of
# putting every XDG cache outside home at runtime; see AGENTS.md.
RUN set -e; \
    configured="$(sed -n 's/^node = "\(.*\)"/\1/p' /opt/mise/config.toml)"; \
    if [ "$configured" != "${NODE_VERSION}" ]; then \
      echo "node version mismatch: mise.toml wants '${configured}', Containerfile NODE_VERSION is '${NODE_VERSION}'" >&2; \
      exit 1; \
    fi; \
    mise install; \
    mise reshim --force; \
    for shim in fd git-lfs jq nvim rg shfmt shellcheck tmux; do \
      [ -x "/opt/mise/shims/$shim" ] || { echo "missing shim for baked tool: $shim" >&2; exit 1; }; \
    done; \
    node --version; \
    bb --version; \
    rm -rf "/home/${USERNAME}/.cache" "/home/${USERNAME}/.local"

# ---------------------------------------------------------------------------
# Locale, editor, login-shell PATH, and the neovim alias.
#
# This block sits last on purpose. An ENV invalidates every layer below it, so
# putting LANG up with the other ENVs would force node, bb and Playwright's
# Chromium to rebuild. Nothing above needs these values.
# ---------------------------------------------------------------------------

# LANG is unset in the base image and LC_CTYPE lands on POSIX, which shows up as
# encoding trouble in anything that prints non-ASCII. C.UTF-8 needs no locales
# package on Debian 13.
ENV LANG=C.UTF-8
# git reaches for $EDITOR for `git commit` without -m and for `git rebase -i`.
ENV EDITOR=vi
ENV VISUAL=vi

USER root

# Debian's /etc/profile resets PATH outright, which drops the mise shims, so a login
# shell (`bash -l`, ssh, or anything bb spawns through one) loses every lazy tool and
# they all become "command not found". Image-owned, so unlike ~/.bashrc this is not
# frozen into the home volume and can still be fixed after a volume exists.
RUN printf '%s\n' \
      '# Debian /etc/profile resets PATH, which drops the mise shims. Put them back.' \
      'case ":$PATH:" in' \
      '  *:/opt/mise/shims:*) ;;' \
      '  *) PATH="/opt/mise/shims:$PATH" ;;' \
      'esac' \
      'export PATH' \
      > /etc/profile.d/mise-shims.sh \
    && chmod 0644 /etc/profile.d/mise-shims.sh

# neovim as vi and vim, for the whole container.
#
# These must be wrapper scripts and not symlinks. mise's shims are symlinks to the
# mise binary and it dispatches on the tool name in argv[0], so a shim reached as
# "vim" is rejected with "vim is not a valid shim". `exec nvim` re-enters through the
# shim under its real name instead. mise's neovim declares bins = ["nvim"], so no
# vim/vi shim exists to shadow these, and the loop refuses to continue if that ever
# changes. See AGENTS.md before replacing this with a symlink.
RUN set -e; \
    for name in vi vim; do \
      if [ -e "/opt/mise/shims/$name" ]; then \
        echo "refusing to shadow the $name shim with the neovim wrapper" >&2; \
        exit 1; \
      fi; \
      printf '%s\n' '#!/bin/sh' \
        '# neovim, aliased for the whole container. Not a symlink, see AGENTS.md.' \
        'exec nvim "$@"' \
        > "/usr/local/bin/$name"; \
      chmod 0755 "/usr/local/bin/$name"; \
    done; \
    HOME=/tmp vi --version | head -1

USER $USERNAME

# Default to serving bb, with the entrypoint forwarding signals so `podman stop`
# is a clean shutdown. Override with a command to get a shell instead:
#   podman run --rm -it bb:dev /bin/bash
CMD ["bash", "/home/developer/entrypoint.sh"]
