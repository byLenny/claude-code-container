#!/bin/bash
# Run this after cloning a new repo into /workspace to get it a Remote
# Control session without restarting the container.
set -euo pipefail

echo "Scanning /workspace for repos..."
# No sudo needed: /etc/supervisor/generated is dev-owned, and
# supervisord's RPC interface (which supervisorctl talks to) has no auth,
# only a 127.0.0.1-only listener. -c is required because it lives at a
# non-default config path -- plain `supervisorctl` looks for a unix
# socket this project never creates and fails outright.
bash /opt/scripts/gen-supervisor-repos.sh
echo "Reloading supervisord..."
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf reread
supervisorctl -c /etc/supervisor/conf.d/supervisord.conf update
echo "Done. Check status with:" \
     "supervisorctl -c /etc/supervisor/conf.d/supervisord.conf status"
