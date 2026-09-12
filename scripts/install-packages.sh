#!/bin/bash
# Diffs packages.txt against what's actually installed, shows a short
# description of anything pending, and asks for confirmation before
# installing. Pass --yes to skip the prompt (used non-interactively
# at container boot for already-approved packages).
set -euo pipefail
PACKAGES_FILE=/workspace/.devtools/packages.txt
AUTO_YES=0
[ "${1:-}" = "--yes" ] && AUTO_YES=1

mkdir -p "$(dirname "$PACKAGES_FILE")"
touch "$PACKAGES_FILE"

mapfile -t TRACKED < <(grep -vE '^\s*(#|$)' "$PACKAGES_FILE" || true)
if [ "${#TRACKED[@]}" -eq 0 ]; then
    echo "No packages tracked yet. Use: add-package <name>"
    exit 0
fi

PENDING=()
for pkg in "${TRACKED[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        PENDING+=("$pkg")
    fi
done

if [ "${#PENDING[@]}" -eq 0 ]; then
    echo "All tracked packages are already installed. Nothing to do."
    exit 0
fi

echo "The following tracked packages are not yet installed:"
echo ""
sudo apt-get update -qq
for pkg in "${PENDING[@]}"; do
    desc=$(apt-cache show "$pkg" 2>/dev/null | grep -m1 '^Description:' | sed 's/^Description: //')
    printf "  %-25s %s\n" "$pkg" "${desc:-(no description found — check the package name)}"
done
echo ""

if [ "$AUTO_YES" -eq 0 ]; then
    read -rp "Install these ${#PENDING[@]} package(s)? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted. Nothing installed."
        exit 0
    fi
fi

sudo apt-get install -y --no-install-recommends "${PENDING[@]}"
echo "Installed ${#PENDING[@]} package(s)."
