FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# --- Base toolchain -----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        git tmux curl wget ca-certificates sudo gnupg \
        build-essential python3 python3-pip python3-venv \
        ripgrep jq unzip less \
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

# --- Non-root user with scoped sudo for package management --------------
RUN useradd -m -s /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt" > /etc/sudoers.d/dev-apt \
    && chmod 0440 /etc/sudoers.d/dev-apt

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
    && ln -sf /opt/scripts/rescan-repos.sh /usr/local/bin/rescan-repos

WORKDIR /workspace
EXPOSE 8080

ENTRYPOINT ["/opt/entrypoint.sh"]
