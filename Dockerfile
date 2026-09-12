FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
# Bump deliberately for a newer ttyd release — checked against its
# published SHA256SUMS below, since (unlike the apt sources above) this
# is an unsigned GitHub release binary, not a gpg-verified repo.
ARG TTYD_VERSION=1.7.7

# --- Base toolchain -----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        git tmux curl wget ca-certificates sudo gnupg \
        build-essential python3 python3-pip python3-venv \
        ripgrep jq unzip zip less shellcheck \
        supervisor \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @anthropic-ai/claude-code \
    && rm -rf /var/lib/apt/lists/*

# --- Docker CLI only (no daemon) — used only if /var/run/docker.sock is  --
# bind-mounted at runtime via docker-compose.docker-access.yml. Installing
# the CLI here doesn't grant access on its own; entrypoint.sh checks for
# the socket and wires up group membership at container start.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# --- GitHub CLI — used to authenticate git clones with GH_TOKEN ---------
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli.gpg \
    && chmod a+r /etc/apt/keyrings/githubcli.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# --- ttyd — browser terminal used only for the one-time Claude Code login -
# Gated by TTYD_TOKEN (see scripts/gen-supervisor-login-terminal.sh); only
# ever runs `claude` for /login, nothing else.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) TTYD_ARCH=x86_64 ;; \
        arm64) TTYD_ARCH=aarch64 ;; \
        armhf) TTYD_ARCH=armhf ;; \
        *) echo "Unsupported architecture for ttyd: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
        -o /usr/local/bin/ttyd; \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/SHA256SUMS" \
        -o /tmp/ttyd.sha256sums; \
    grep -E "[[:space:]]ttyd\.${TTYD_ARCH}\$" /tmp/ttyd.sha256sums \
        | sed "s#ttyd\.${TTYD_ARCH}#/usr/local/bin/ttyd#" \
        | sha256sum -c -; \
    rm -f /tmp/ttyd.sha256sums; \
    chmod +x /usr/local/bin/ttyd

# --- Non-root user with scoped sudo for package management --------------
RUN useradd -m -s /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt" > /etc/sudoers.d/dev-apt \
    && chmod 0440 /etc/sudoers.d/dev-apt

# --- SDKMAN + JDKs (17, 21 LTS + current latest) -------------------------
# Non-LTS Java releases (18-20, 22-24, ...) get pulled from every
# distributor once the next one supersedes them — none of them are
# downloadable from anywhere anymore. Only the LTS releases plus whatever's
# currently latest stay realistically installable long-term, so that's what
# this preloads. Bump these identifiers periodically; see current ones with:
#   curl -s https://api.sdkman.io/2/candidates/java/linux/versions/list
ARG JDK17_VERSION=17.0.20-tem
ARG JDK21_VERSION=21.0.12+1.1-tem
ARG JDK_LATEST_VERSION=26.0.2+1.1-tem
RUN export JDK17_VERSION="${JDK17_VERSION}" JDK21_VERSION="${JDK21_VERSION}" JDK_LATEST_VERSION="${JDK_LATEST_VERSION}" \
    && su -s /bin/bash -c ' \
        set -e; \
        curl -s https://get.sdkman.io | bash; \
        CONFIG="$HOME/.sdkman/etc/config"; \
        if grep -q "^sdkman_auto_answer=" "$CONFIG"; then \
            sed -i "s/^sdkman_auto_answer=.*/sdkman_auto_answer=true/" "$CONFIG"; \
        else \
            echo "sdkman_auto_answer=true" >> "$CONFIG"; \
        fi; \
        source "$HOME/.sdkman/bin/sdkman-init.sh"; \
        sdk install java "$JDK17_VERSION"; \
        sdk install java "$JDK21_VERSION"; \
        sdk install java "$JDK_LATEST_VERSION"; \
        sdk default java "$JDK21_VERSION" \
    ' dev

# JAVA_HOME/PATH set at the image level (not just dev's .bashrc) so java
# works in every context: interactive shells, Claude Code's own bash tool,
# and supervisord-spawned Remote Control sessions alike. Points at SDKMAN's
# "current" symlink, i.e. whatever `sdk default java` last set (21 above) —
# switch it per-session with `sdk use java <version>` if you need 17 or the
# latest instead.
ENV JAVA_HOME=/home/dev/.sdkman/candidates/java/current
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- Web UI dependencies --------------------------------------------------
COPY webui/requirements.txt /opt/webui/requirements.txt
RUN pip3 install --break-system-packages --no-cache-dir -r /opt/webui/requirements.txt

# --- App files ------------------------------------------------------------
COPY scripts/ /opt/scripts/
COPY webui/ /opt/webui/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/scripts/*.sh /opt/entrypoint.sh \
    && mkdir -p /var/log/claude-sessions /etc/supervisor/generated \
    && chown -R dev:dev /opt/scripts /opt/webui /var/log/claude-sessions /etc/supervisor/generated \
    && ln -sf /opt/scripts/add-package.sh /usr/local/bin/add-package \
    && ln -sf /opt/scripts/install-packages.sh /usr/local/bin/install-packages \
    && ln -sf /opt/scripts/slim-packages.sh /usr/local/bin/slim-packages \
    && ln -sf /opt/scripts/rescan-repos.sh /usr/local/bin/rescan-repos \
    && ln -sf /opt/scripts/clone-repo.sh /usr/local/bin/clone-repo \
    && ln -sf /opt/scripts/list-repos.sh /usr/local/bin/list-repos

WORKDIR /workspace
EXPOSE 8080 7681

ENTRYPOINT ["/opt/entrypoint.sh"]
