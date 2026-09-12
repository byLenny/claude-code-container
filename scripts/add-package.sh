#!/bin/bash
# Usage: add-package <apt-package> [<apt-package> ...]
# Appends packages to the tracked list. Doesn't install anything —
# run `install-packages` afterwards to review and apply.
set -euo pipefail
PACKAGES_FILE=/workspace/.devtools/packages.txt

if [ "$#" -eq 0 ]; then
    echo "Usage: add-package <apt-package> [<apt-package> ...]"
    exit 1
fi

mkdir -p "$(dirname "$PACKAGES_FILE")"
touch "$PACKAGES_FILE"

added=0
for pkg in "$@"; do
    if grep -qxF "$pkg" "$PACKAGES_FILE" 2>/dev/null; then
        echo "  (already tracked) $pkg"
    else
        echo "$pkg" >> "$PACKAGES_FILE"
        echo "  + $pkg"
        added=$((added + 1))
    fi
done

if [ "$added" -gt 0 ]; then
    echo ""
    echo "Added $added package(s) to $PACKAGES_FILE."
    echo "Run 'install-packages' to review and install them now,"
    echo "or they'll be applied automatically next container start."
fi
