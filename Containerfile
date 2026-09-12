# Pinned to the multi-arch OCI index digest for reproducible builds.
# Bump with: podman images --digests | grep debian
FROM docker.io/library/debian@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

# Scoped to the build rather than ENV, so it does not leak into the final image.
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
                       build-essential \
                       ca-certificates \
                       curl \
                       git \
                       libpq-dev \
                       libsqlite3-dev \
                       libssl-dev \
                       openssh-client \
                       postgresql-client \
                       sqlite3 \
                       zlib1g-dev \
                       zsh \
    && rm -rf /var/lib/apt/lists/*

ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME

# bb hosts many projects and resolves them by path, so home is the sane default
# rather than a single mount point. Mount a tree under it (see the Makefile).
USER $USERNAME
WORKDIR /home/${USERNAME}

# The installer verifies the release checksum. Pinning MISE_VERSION keeps the
# build reproducible and selects the checksum from that release's SHASUMS256.txt.
ARG MISE_VERSION=2026.9.5
RUN curl -fsSL https://mise.run | MISE_VERSION="v${MISE_VERSION}" sh

# ~/.local/bin is where mise.run installs the binary. ~/.local/share/mise/shims
# is the shim farm that resolves tools in non-interactive processes, which is
# how bb spawns agent CLIs.
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:$PATH"

# ---------------------------------------------------------------------------
# Everything above depends only on the base image, mise, and the versions named
# in this file. Everything below is split so that the expensive layers do not
# depend on mise.toml: editing the toolset would otherwise re-download node and
# reinstall bb on every change.
# ---------------------------------------------------------------------------

# node is the runtime the image is built around, so it is installed from an
# explicit version rather than read out of mise.toml. That means the version is
# named twice, here and in mise.toml, because a layer cannot both install node
# and depend on the file that declares it. The check further down fails the
# build if the two drift apart.
ARG NODE_VERSION=24.21.0
RUN mkdir -p /home/${USERNAME}/.config/mise \
    && printf '[tools]\nnode = "%s"\n' "${NODE_VERSION}" > /home/${USERNAME}/.config/mise/config.toml \
    && mise install \
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

# ~/.bb holds server state. Creating it as the developer user means a named
# volume mounted at that path inherits the right uid/gid instead of starting out
# root-owned, which would stop bb from writing to it.
RUN mkdir -p /home/${USERNAME}/.bb

# Interactive shells get full activation for env vars and hooks. Shims stay on
# PATH for non-interactive processes.
RUN printf '%s\n' 'eval "$(mise activate bash)"' >> /home/${USERNAME}/.bashrc \
    && printf '%s\n' 'eval "$(mise activate zsh)"' >> /home/${USERNAME}/.zshrc

COPY --chown=$USERNAME:$USERNAME scripts/entrypoint.sh /home/${USERNAME}/entrypoint.sh

# ---------------------------------------------------------------------------
# The toolset. Only this and below rebuild when mise.toml changes.
# ---------------------------------------------------------------------------

# The toolset is installed as the *global* config. Global config is always
# trusted, so no `mise trust` step is needed, and mounted projects can still
# override it with their own mise.toml. This overwrites the bootstrap config
# written above.
COPY --chown=$USERNAME:$USERNAME mise.toml /home/${USERNAME}/.config/mise/config.toml

# Catch a NODE_VERSION that no longer matches the toolset rather than shipping
# an image whose node is not the one mise reports. Then reconcile the shim farm
# with the real toolset, which is cheap: node is already installed and the rest
# of the tools are lazy, so this only creates their bootstrap shims.
RUN set -e; \
    configured="$(sed -n 's/^node = "\(.*\)"/\1/p' /home/${USERNAME}/.config/mise/config.toml)"; \
    if [ "$configured" != "${NODE_VERSION}" ]; then \
      echo "node version mismatch: mise.toml wants '${configured}', Containerfile NODE_VERSION is '${NODE_VERSION}'" >&2; \
      exit 1; \
    fi; \
    mise install; \
    mise reshim --force; \
    node --version; \
    bb --version

# Default to serving bb, with the entrypoint forwarding signals so `podman stop`
# is a clean shutdown. Override with a command to get a shell instead:
#   podman run --rm -it bb:dev /bin/bash
CMD ["bash", "/home/developer/entrypoint.sh"]
