#!/bin/bash
# Run this after cloning a new repo into /workspace to get it a Remote
# Control session without restarting the container.
set -euo pipefail

echo "Scanning /workspace for repos..."
sudo bash /opt/scripts/gen-supervisor-repos.sh
echo "Reloading supervisord..."
sudo supervisorctl reread
sudo supervisorctl update
echo "Done. Check status with: supervisorctl status"
