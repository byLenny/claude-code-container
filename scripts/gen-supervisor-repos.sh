#!/bin/bash
# Regenerates one supervisord program per git repo under /workspace.
# Safe to re-run any time (e.g. after cloning a new repo) — call
# `rescan-repos` afterwards to pick it up without a container restart.
set -euo pipefail

WORKSPACE=/workspace
GENERATED_DIR=/etc/supervisor/generated
CLAUDE_HOME=/home/dev/.claude
LOG_DIR=/var/log/claude-sessions

mkdir -p "$GENERATED_DIR" "$LOG_DIR"

AUTHENTICATED=0
if find "$CLAUDE_HOME" -maxdepth 1 -iname '*credential*' -o -iname '*.session*' 2>/dev/null | grep -q .; then
    AUTHENTICATED=1
fi
AUTOSTART=$([ "$AUTHENTICATED" -eq 1 ] && echo true || echo false)

# Only clear out previously-generated *repo* programs. claude-terminal.conf
# is managed separately by gen-supervisor-terminal.sh — a blanket `rm *.conf`
# here would delete it every time this runs (every boot, plus every
# rescan-repos/clone-repo), silently killing the browser terminal.
find "$GENERATED_DIR" -maxdepth 1 -name 'claude-*.conf' ! -name 'claude-terminal.conf' -delete

count=0
for dir in "$WORKSPACE"/*/; do
    repo="$(basename "$dir")"
    [ "$repo" = ".devtools" ] && continue
    [ -d "$dir/.git" ] || continue
    if [ "$repo" = "terminal" ]; then
        echo "  ! skipping repo named 'terminal' — that name is reserved for" \
             "the browser terminal's own supervisor program"
        continue
    fi

    cat > "$GENERATED_DIR/claude-${repo}.conf" <<EOF
[program:claude-${repo}]
command=claude remote-control --spawn worktree --name "${repo}" --no-sandbox
directory=${dir%/}
user=dev
autostart=${AUTOSTART}
autorestart=true
startretries=1000
environment=HOME="/home/dev"
stdout_logfile=${LOG_DIR}/${repo}.log
stderr_logfile=${LOG_DIR}/${repo}.log
stopsignal=INT
EOF
    echo "  + ${repo}"
    count=$((count + 1))
done
echo "${count} repo session(s) configured (autostart=${AUTOSTART})"
