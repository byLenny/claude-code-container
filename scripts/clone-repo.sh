#!/bin/bash
# Clone a repo you have GitHub access to straight into /workspace and give
# it a Remote Control session immediately — no host-side step needed.
#
# Usage: clone-repo <owner>/<repo>|<url> [target-name]
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: clone-repo <owner>/<repo>|<url> [target-name]"
    exit 1
fi

SOURCE="$1"
WORKSPACE=/workspace

# This is reachable over HTTP from the web dashboard's /clone form, not
# just via `docker exec` from someone who already has a shell -- so
# SOURCE and target-name are untrusted input, not just typo-prone ones.
# A leading '-' would let SOURCE be parsed as a git/gh flag instead of a
# repo reference (the classic clone-argument-injection class of bug,
# e.g. an --upload-pack= payload) -- refuse it outright.
case "$SOURCE" in
    -*)
        echo "Refusing a source starting with '-' — that looks like a flag," >&2
        echo "not a repo reference or URL." >&2
        exit 1
        ;;
esac

if ! su -s /bin/bash -c 'gh auth status' dev >/dev/null 2>&1; then
    echo "gh is not authenticated — set GH_TOKEN in .env and recreate the" >&2
    echo "container, or run 'gh auth login' inside it as the dev user." >&2
    exit 1
fi

if [ -n "${2:-}" ]; then
    NAME="$2"
    # NAME becomes $WORKSPACE/$NAME below with no further checks -- an
    # unrestricted value (e.g. containing '/' or '..') could write
    # outside /workspace entirely. basename below can't do that (it
    # always strips directory components), so this only needs to guard
    # the explicit target-name case.
    if ! [[ "$NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "target-name must be letters, digits, '.', '-', '_' only (no '/')." >&2
        exit 1
    fi
else
    NAME="$(basename "$SOURCE" .git)"
fi

TARGET="$WORKSPACE/$NAME"
if [ -e "$TARGET" ]; then
    echo "$TARGET already exists — pick a different target-name or remove it first." >&2
    exit 1
fi

echo "Cloning $SOURCE into $TARGET..."
# Clone as 'dev' (this script is normally invoked as root via `docker exec`)
# so the repo — and the Remote Control session that runs as 'dev' — can
# actually read/write it.
export CLONE_SOURCE="$SOURCE" CLONE_TARGET="$TARGET"
# shellcheck disable=SC2016  # meant to expand in the 'dev' shell su starts, not here
su -s /bin/bash -c 'gh repo clone "$CLONE_SOURCE" "$CLONE_TARGET"' dev

echo "Registering Remote Control session..."
# No sudo needed for any of this: /etc/supervisor/generated is dev-owned,
# and supervisord's RPC interface (which supervisorctl talks to) has no
# auth configured, only a 127.0.0.1-only listener -- so this works whether
# this script is invoked as root (via `docker exec`) or as dev (from the
# web dashboard).
bash /opt/scripts/gen-supervisor-repos.sh
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf reread
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf update

echo "Done. '$NAME' is cloned and its session is starting — check the web" \
     "dashboard or 'supervisorctl -c /etc/supervisor/conf.d/supervisord.conf status'."
