#!/bin/bash
# Lists repos the authenticated GitHub account can access, as a quick
# reference for what you can pass to `clone-repo`.
# Usage: list-repos [gh-repo-list-args...]   (e.g. list-repos --limit 200)
set -euo pipefail

if ! su -s /bin/bash -c 'gh auth status' dev >/dev/null 2>&1; then
    echo "gh is not authenticated — set GH_TOKEN in .env and recreate the" >&2
    echo "container, or run 'gh auth login' inside it as the dev user." >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    su -s /bin/bash -c 'gh repo list --limit 100' dev
else
    su -s /bin/bash -c 'gh repo list "$@"' dev _ "$@"
fi
