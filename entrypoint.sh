#!/bin/bash
set -euo pipefail

WORKSPACE=/workspace
DEVTOOLS_DIR="$WORKSPACE/.devtools"
PACKAGES_FILE="$DEVTOOLS_DIR/packages.txt"
GENERATED_DIR=/etc/supervisor/generated
CLAUDE_HOME=/home/dev/.claude
LOG_DIR=/var/log/claude-sessions

mkdir -p "$DEVTOOLS_DIR" "$GENERATED_DIR" "$LOG_DIR"
touch "$PACKAGES_FILE"
chown -R dev:dev "$DEVTOOLS_DIR" "$LOG_DIR"

echo "==> [1/3] Re-applying approved packages from $PACKAGES_FILE"
# Non-interactive: this file only ever contains packages that were already
# reviewed via install-packages.sh, so re-provisioning them on every boot
# (needed because plain container recreation loses anything installed ad hoc)
# does not need another confirmation prompt.
bash /opt/scripts/install-packages.sh --yes || \
    echo "!! Some packages in packages.txt failed to install — check the list for typos."
rm -rf /var/lib/apt/lists/*

echo "==> [2/4] Checking for optional Docker socket access"
DOCKER_SOCK=/var/run/docker.sock
if [ -S "$DOCKER_SOCK" ]; then
    SOCK_GID=$(stat -c '%g' "$DOCKER_SOCK")
    GROUP_NAME=$(getent group "$SOCK_GID" | cut -d: -f1)
    if [ -z "$GROUP_NAME" ]; then
        GROUP_NAME=docker
        groupadd -g "$SOCK_GID" "$GROUP_NAME" 2>/dev/null || groupadd "$GROUP_NAME"
    fi
    usermod -aG "$GROUP_NAME" dev
    echo "    docker.sock detected (gid $SOCK_GID) — 'dev' added to group '$GROUP_NAME'."
    echo "    Claude Code inside this container can now build/run containers."
else
    echo "    (not mounted — this container has no Docker access. See"
    echo "     docker-compose.docker-access.yml to enable it.)"
fi

echo "==> [3/4] Checking Claude Code authentication"
mkdir -p "$CLAUDE_HOME"
chown -R dev:dev /home/dev
AUTHENTICATED=0
if find "$CLAUDE_HOME" -maxdepth 1 -iname '*credential*' -o -iname '*.session*' 2>/dev/null | grep -q .; then
    AUTHENTICATED=1
fi

if [ "$AUTHENTICATED" -eq 0 ]; then
    cat <<'EOF'

    ############################################################
    #  No saved Claude Code login found in the claude-config    #
    #  volume yet. Remote Control needs a one-time interactive  #
    #  OAuth login (headless tokens are not accepted for it).   #
    #                                                            #
    #  Run this once, from the host:                             #
    #    docker exec -it claude-dev sudo -u dev claude           #
    #    then run /login inside it and accept workspace trust.   #
    #                                                            #
    #  After that, this container will authenticate               #
    #  automatically on every future start/restart.               #
    ############################################################

EOF
else
    echo "    Found persisted login — sessions will authenticate automatically."
fi

echo "==> [4/4] Generating one Remote Control session per repo in $WORKSPACE"
bash /opt/scripts/gen-supervisor-repos.sh

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
