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

if ! su -s /bin/bash -c 'gh auth status' dev >/dev/null 2>&1; then
    echo "gh is not authenticated — set GH_TOKEN in .env and recreate the" >&2
    echo "container, or run 'gh auth login' inside it as the dev user." >&2
    exit 1
fi

if [ -n "${2:-}" ]; then
    NAME="$2"
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
sudo bash /opt/scripts/gen-supervisor-repos.sh
sudo supervisorctl reread
sudo supervisorctl update

echo "Done. '$NAME' is cloned and its session is starting — check the web dashboard or 'supervisorctl status'."
