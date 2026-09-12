# claude-dev — multi-repo Claude Code Remote Control box

A Docker container that runs `claude remote-control` for every git repo you
drop into `/workspace`, keeps those sessions alive automatically, tracks
extra apt packages in a reviewable file, and gives you a small web dashboard
with a QR code per session so you can connect from the Claude mobile app or
desktop app.

New here? [SETUP.md](SETUP.md) walks through first-time setup step by step.
This README is the quicker reference.

## First-time setup

Optional but recommended — enables cloning repos from inside the container
(see [Adding repos](#adding-repos)):

```bash
cp .env.example .env
# edit .env and set GH_TOKEN to a GitHub personal access token
# (fine-grained with Contents read/write, or classic with the `repo` scope)
```

```bash
docker compose up -d --build
```

Claude Code's Remote Control requires a **full interactive OAuth login** —
API keys and `claude setup-token` don't work for it, so this one step can't
be automated. Do it once:

```bash
docker exec -it claude-dev sudo -u dev claude
# inside: run /login, finish the browser OAuth flow, accept workspace trust, then exit
```

The login is stored in the `claude-config` volume, so it survives restarts
and `docker compose up -d --build` afterwards — you won't need to log in
again unless you delete that volume.

Restart the container once after logging in so it picks up the credentials
and starts the per-repo sessions automatically:

```bash
docker compose restart
```

## Adding repos

With `GH_TOKEN` set (see First-time setup), clone straight from inside the
container — no host-side git needed:

```bash
docker exec -it claude-dev list-repos              # see what you have access to
docker exec -it claude-dev clone-repo owner/repo    # clone + start its session
docker exec -it claude-dev clone-repo owner/repo my-custom-name
```

`clone-repo` accepts anything `gh repo clone` does (`owner/repo`, a full
`https://github.com/...` URL, etc.), clones it into `./workspace/<name>`, and
registers its Remote Control session immediately — equivalent to running
`rescan-repos` afterwards, just in one step.

You can still clone (or copy) a repo into `./workspace/<name>` on the host
yourself instead, then either:

```bash
docker exec -it claude-dev rescan-repos   # picks it up immediately, no restart
```

or just restart the container. Either way, each repo gets its own `claude
remote-control --spawn worktree --name <repo>` session, supervised and
auto-restarted if it crashes or the network drops for a while.

## Web dashboard

Open `http://<host>:8080` (bound to `127.0.0.1` in the compose file on
purpose — put it behind Caddy/Tailscale rather than exposing it directly).
It lists every repo's session status and a QR code for pairing the Claude
mobile app. The URL is also shown as a link for connecting from a desktop
browser or the Claude desktop app — both share the same session list since
it's tied to your account, not the device.

## Installing extra tools

```bash
docker exec -it claude-dev add-package ffmpeg
docker exec -it claude-dev install-packages     # shows what's pending, asks to confirm
```

Approved packages live in `workspace/.devtools/packages.txt` (bind-mounted,
so it survives container recreation) and get silently re-installed on every
container start — no re-confirmation needed since they were already
reviewed once.

To trim packages you no longer need:

```bash
docker exec -it claude-dev slim-packages
```

This scans your repos for references to each tracked package and suggests
(never auto-applies beyond editing the tracked list) removing ones that
don't seem to be used by anything currently in `/workspace`.

## Optional: Docker control from inside the container

Off by default. The image includes the Docker CLI (no daemon), but the
socket itself is only mounted if you opt in:

```bash
docker compose -f docker-compose.yml -f docker-compose.docker-access.yml up -d
```

`entrypoint.sh` detects the mounted socket at boot, creates/matches a group
for its GID, and adds `dev` to it — so `docker ps`, `docker build`, etc.
work inside the container without hardcoding a GID that varies per host.

**This is root-equivalent access to your host** — anything with access to
the socket can start a privileged container and read/write the whole
filesystem. Only enable it if that tradeoff is acceptable for this box.
To turn it back off, go back to `docker compose up -d` without the override
file and recreate the container.

## Notes / things to decide

- **Sandbox flag**: sessions run with `--no-sandbox` since Docker itself is
  already the isolation boundary here; switch to `--sandbox` per repo in
  `scripts/gen-supervisor-repos.sh` if you want Claude Code's own
  filesystem/network sandboxing layered on top.
- **Reachability**: Remote Control is outbound-HTTPS-only, so no inbound
  port-forwarding is needed for the sessions themselves — only the
  dashboard (port 8080) needs exposing, and only to devices you trust.
