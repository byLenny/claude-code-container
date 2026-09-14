# Ideas from similar projects

Notes gathered while surveying other Docker + Claude Code setups (HolyClaude, HolyCode, ClaudeBox, claude-code-docker, and Anthropic's own Remote Control). Not a commitment to build any of these — just a running list of patterns worth considering.

## Bootstrap-once pattern (from HolyClaude)
On first container start, run a `bootstrap.sh` that sets up default settings, a memory template, and git identity — then drop a sentinel file (e.g. `.bootstrapped`) so it never re-runs. Means re-pulling the image or restarting the container doesn't clobber customizations. Fits naturally into the existing supervisord startup sequence.

## Per-repo auth/config isolation (from ClaudeBox)
ClaudeBox gives each project its own image, auth state, shell history, and config, instead of one shared container identity. Our current design mounts multiple repos into one container with a single shared OAuth session — simpler, but all repos share session/auth state. Consider namespacing config per repo (e.g. `/data/<repo>/.claude/` instead of one global `~/.claude`) to prevent state bleed between repos, without going as far as separate images per project.

## Network allowlist per session (from ClaudeBox)
ClaudeBox has a `firewall allowlist` command to view/edit which domains a container can reach. Worth adding given the dashboard has optional Docker socket access — a visible, editable egress allowlist per session would limit blast radius if a session does something unexpected. Could pair well with the existing homelab Gluetun+Mullvad egress setup.

## Push notifications on session completion/input-needed (from HolyClaude)
HolyClaude integrates Apprise (100+ notification services) to ping when a long session finishes or needs input. Given the whole point of this project is phone-based control, this is probably the highest-value addition on this list — avoids having to poll the dashboard.

## Version-pinned Claude Code CLI (from claude-code-docker)
Pin the CLI version in the Dockerfile instead of always installing latest. Gives reproducible builds and control over update timing instead of being surprised by a CLI change mid-session.

## Slim vs. full image split (from HolyClaude)
Ship a lean base image with core tools only; let Claude install anything extra on-demand when a task actually needs it. Keeps base image size down since most sessions never touch most pre-installed tooling anyway.

## Agent-board / task-queue UI (from HolyCode's Paperclip, lower priority)
Longer-term direction: instead of manually starting a session per repo, a dashboard where you "assign" work per repo and sessions wake on a trigger/heartbeat. More a UX evolution of the existing Flask dashboard than new infrastructure — worth keeping in mind, not urgent.
