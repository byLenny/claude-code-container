#!/bin/bash
# Regenerates the supervisord program for the browser-based terminal
# (ttyd) — a general-purpose interactive shell as the 'dev' user, in
# /workspace. Only generated if WEB_TOKEN is set, since that's the only
# thing gating access to a full shell over HTTP. (entrypoint.sh has
# already normalized the old TTYD_TOKEN name into WEB_TOKEN by the time
# this runs, so this script only needs to know about the new name.)
set -euo pipefail

GENERATED_DIR=/etc/supervisor/generated
LOG_DIR=/var/log/claude-sessions
CONF="$GENERATED_DIR/claude-terminal.conf"

mkdir -p "$GENERATED_DIR" "$LOG_DIR"
rm -f "$CONF"

if [ -z "${WEB_TOKEN:-}" ]; then
    echo "    WEB_TOKEN not set — browser terminal disabled. Use"
    echo "    'docker exec -it claude-dev sudo -u dev bash' instead, or"
    echo "    set WEB_TOKEN in .env to enable http://<host>:7681."
    exit 0
fi

# Embedded directly into a generated INI file below, so restrict the
# charset to avoid breaking supervisord's config parser (';' starts a
# comment, '%' triggers its own expansion syntax, etc.).
if ! [[ "$WEB_TOKEN" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "    !! WEB_TOKEN contains characters other than letters, digits,"
    echo "       '-' or '_' — refusing to enable the browser terminal."
    echo "       Change it in .env to a plain token and restart."
    exit 0
fi

# Sessions are backed by tmux (see terminal-attach.sh), a separate daemon
# ttyd's connection doesn't own, so a session keeps running -- and stays
# reachable by name -- independent of any one ttyd connection. --url-arg
# lets each connection's URL (?arg=<session>&arg=<folder>, wired up by
# the dashboard) pick which session terminal-attach.sh attaches to (or
# creates); no args at all falls back to the original single "main"
# session in /workspace. Multiple sessions this way means multiple
# people can genuinely be connected at once (each to their own session,
# or several to the same one) -- so --once is dropped too; ttyd now runs
# directly as dev (no su needed, since there's no longer a fixed command
# that has to run as root first) and spawns terminal-attach.sh fresh per
# connection.
cat > "$CONF" <<EOF
[program:claude-terminal]
command=/usr/local/bin/ttyd --url-arg --writable -p 7681 -c "dev:${WEB_TOKEN}" /opt/scripts/terminal-attach.sh
directory=/workspace
user=dev
autostart=true
autorestart=true
startretries=1000
environment=HOME="/home/dev"
stdout_logfile=${LOG_DIR}/terminal.log
stderr_logfile=${LOG_DIR}/terminal.log
stopsignal=INT
EOF

echo "    WEB_TOKEN set — browser terminal enabled at http://<host>:7681"
echo "    (username 'dev', password is WEB_TOKEN). This is a full interactive"
echo "    shell as 'dev' — same access any Claude Code session already has."
echo "    Each tmux-backed session survives closing the tab -- reconnect (or"
echo "    open one from the dashboard) to pick up where you left off. Typing"
echo "    'exit' at the shell prompt (not inside 'claude') ends that session"
echo "    for good instead of just detaching from it."
