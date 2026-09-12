#!/bin/bash
# Heuristic-based suggestion tool: scans every repo under /workspace for
# clues that a tracked package is still needed (manifest files, README/CI
# mentions, Dockerfiles calling apt-get install <pkg>). Anything tracked
# but never referenced anywhere is proposed as a removal candidate.
#
# This never uninstalls or edits packages.txt on its own — it only prints
# a suggested diff and, if you confirm, removes lines from packages.txt.
# The packages themselves stay installed until the next full rebuild.
set -euo pipefail
PACKAGES_FILE=/workspace/.devtools/packages.txt
WORKSPACE=/workspace

touch "$PACKAGES_FILE"
mapfile -t TRACKED < <(grep -vE '^\s*(#|$)' "$PACKAGES_FILE" || true)

if [ "${#TRACKED[@]}" -eq 0 ]; then
    echo "Nothing tracked yet."
    exit 0
fi

echo "Scanning repos under $WORKSPACE for references to tracked packages..."
CANDIDATES=()
for pkg in "${TRACKED[@]}"; do
    if grep -rIl --exclude-dir=.git -e "$pkg" "$WORKSPACE" >/dev/null 2>&1; then
        continue
    fi
    CANDIDATES+=("$pkg")
done

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
    echo "No unreferenced packages found — packages.txt looks lean already."
    exit 0
fi

echo ""
echo "These tracked packages aren't mentioned anywhere in your repos"
echo "(Dockerfiles, READMEs, CI configs, lockfiles, etc.) — they may be"
echo "leftovers from a project you removed or a one-off tool:"
echo ""
for pkg in "${CANDIDATES[@]}"; do
    echo "  - $pkg"
done
echo ""
echo "This is a heuristic, not a guarantee — a package can be needed"
echo "without being named anywhere in the repo (e.g. a transitive build tool)."
read -rp "Remove these ${#CANDIDATES[@]} line(s) from packages.txt? [y/N] " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    tmp=$(mktemp)
    grep -vFf <(printf '%s\n' "${CANDIDATES[@]}") "$PACKAGES_FILE" > "$tmp" || true
    mv "$tmp" "$PACKAGES_FILE"
    echo "Removed. Note: this only edits packages.txt — the packages stay"
    echo "installed in this container until it's rebuilt from scratch."
else
    echo "Left packages.txt unchanged."
fi
