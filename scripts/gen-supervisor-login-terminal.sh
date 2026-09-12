#!/bin/bash
# Regenerates the supervisord program for the browser-based Claude Code
# login terminal (ttyd). It only runs `claude` (for the one-time /login
# flow) as the 'dev' user — nothing else is reachable through it — and
# only if TTYD_TOKEN is set, since that's the only thing gating access to
# a shell-adjacent terminal over HTTP.
set -euo pipefail

GENERATED_DIR=/etc/supervisor/generated
LOG_DIR=/var/log/claude-sessions
CONF="$GENERATED_DIR/claude-login-terminal.conf"

mkdir -p "$GENERATED_DIR" "$LOG_DIR"
rm -f "$CONF"

if [ -z "${TTYD_TOKEN:-}" ]; then
    echo "    TTYD_TOKEN not set — browser login terminal disabled. Use"
    echo "    'docker exec -it claude-dev sudo -u dev claude' instead, or"
    echo "    set TTYD_TOKEN in .env to enable http://<host>:7681."
    exit 0
fi

# Embedded directly into a generated INI file below, so restrict the
# charset to avoid breaking supervisord's config parser (';' starts a
# comment, '%' triggers its own expansion syntax, etc.).
if ! [[ "$TTYD_TOKEN" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "    !! TTYD_TOKEN contains characters other than letters, digits,"
    echo "       '-' or '_' — refusing to enable the browser login terminal."
    echo "       Change it in .env to a plain token and restart."
    exit 0
fi

cat > "$CONF" <<EOF
[program:claude-login-terminal]
command=/usr/local/bin/ttyd --once --writable -p 7681 -c "dev:${TTYD_TOKEN}" su -s /bin/bash -c claude dev
directory=/workspace
user=root
autostart=true
autorestart=true
startretries=1000
environment=HOME="/root"
stdout_logfile=${LOG_DIR}/login-terminal.log
stderr_logfile=${LOG_DIR}/login-terminal.log
stopsignal=INT
EOF

echo "    TTYD_TOKEN set — browser login terminal enabled at http://<host>:7681"
echo "    (username 'dev', password is TTYD_TOKEN). It only ever runs 'claude'"
echo "    and exits after one session — supervisord restarts it for the next use."
