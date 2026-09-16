#!/bin/bash
# Regenerates the supervisord program for the browser-based terminal
# (ttyd) — a general-purpose interactive shell as the 'dev' user, in
# /workspace. Only generated if TTYD_TOKEN is set, since that's the only
# thing gating access to a full shell over HTTP.
set -euo pipefail

GENERATED_DIR=/etc/supervisor/generated
LOG_DIR=/var/log/claude-sessions
CONF="$GENERATED_DIR/claude-terminal.conf"

mkdir -p "$GENERATED_DIR" "$LOG_DIR"
rm -f "$CONF"

if [ -z "${TTYD_TOKEN:-}" ]; then
    echo "    TTYD_TOKEN not set — browser terminal disabled. Use"
    echo "    'docker exec -it claude-dev sudo -u dev bash' instead, or"
    echo "    set TTYD_TOKEN in .env to enable http://<host>:7681."
    exit 0
fi

# Embedded directly into a generated INI file below, so restrict the
# charset to avoid breaking supervisord's config parser (';' starts a
# comment, '%' triggers its own expansion syntax, etc.).
if ! [[ "$TTYD_TOKEN" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "    !! TTYD_TOKEN contains characters other than letters, digits,"
    echo "       '-' or '_' — refusing to enable the browser terminal."
    echo "       Change it in .env to a plain token and restart."
    exit 0
fi

# `--once` means ttyd tears its shell down on every disconnect and
# supervisord starts a fresh one for the next connection (see the comment
# above) -- fine for a one-time login, but it reset any in-progress work
# every time the tab was closed. Routing through a shared tmux session
# ("main") fixes that: tmux is a separate daemon that ttyd's connection
# doesn't own, so it keeps running (and whatever's in it -- shell cwd,
# running commands, scrollback) across ttyd restarts. `new-session -A`
# attaches to "main" if it's already there, or creates it on first
# connect. Note this means the session is shared: whoever connects next
# (with the same TTYD_TOKEN) picks up exactly where the last person left
# off, same as any shared tmux session would.
cat > "$CONF" <<EOF
[program:claude-terminal]
command=/usr/local/bin/ttyd --once --writable -p 7681 -c "dev:${TTYD_TOKEN}" su -s /bin/bash -c "tmux new-session -A -s main" dev
directory=/workspace
user=root
autostart=true
autorestart=true
startretries=1000
environment=HOME="/root"
stdout_logfile=${LOG_DIR}/terminal.log
stderr_logfile=${LOG_DIR}/terminal.log
stopsignal=INT
EOF

echo "    TTYD_TOKEN set — browser terminal enabled at http://<host>:7681"
echo "    (username 'dev', password is TTYD_TOKEN). This is a full interactive"
echo "    shell as 'dev' — same access any Claude Code session already has."
echo "    Each connection joins a shared tmux session ('main'), so closing the"
echo "    tab preserves whatever was running -- reconnect to pick up where you"
echo "    left off. Typing 'exit' at the shell prompt (not inside 'claude')"
echo "    ends that session for good instead of just detaching from it."
