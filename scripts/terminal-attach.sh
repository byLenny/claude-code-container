#!/bin/bash
# Spawned by ttyd (see gen-supervisor-terminal.sh) once per browser
# connection, already running as 'dev'. ttyd's --url-arg flag turns
# ?arg=X&arg=Y query params on the terminal URL into extra positional
# args here: $1 = tmux session name, $2 = starting directory (only used
# the first time that session is created -- an existing session keeps
# its own cwd). Visiting the terminal with no args at all falls back to
# the original single shared "main" session in /workspace.
set -euo pipefail

SESSION="${1:-main}"
FOLDER="${2:-/workspace}"

# Session names become a tmux `-t` target -- tmux treats ':' and '.' as
# session:window.pane separators there, so a name containing them (or
# anything else unexpected from a crafted ?arg=) could target the wrong
# thing. Restrict to a plain, unambiguous charset instead.
if ! [[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]]; then
    SESSION="main"
fi

if [ ! -d "$FOLDER" ]; then
    FOLDER=/workspace
fi

exec tmux new-session -A -s "$SESSION" -c "$FOLDER"
