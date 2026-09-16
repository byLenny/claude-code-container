<p align="center"><img src="webui/static/favicon.svg" width="72" alt="claude-dev icon"></p>

# claude-dev — multi-repo Claude Code Remote Control box

A Docker container that runs `claude remote-control` for every git repo you
drop into `/workspace`, keeps those sessions alive automatically, tracks
extra apt packages in a reviewable file, and gives you a small web dashboard
with a QR code per session so you can connect from the Claude mobile app or
desktop app.

New here? [SETUP.md](SETUP.md) walks through first-time setup step by step.
This README is the quicker reference.

Clone the whole repo onto the machine that will run the container — don't
just copy `docker-compose.yml` out on its own, it builds from the
`Dockerfile`/`entrypoint.sh`/`scripts/`/`webui/` sitting next to it in this
same repo:

```bash
git clone https://github.com/byLenny/claude-code-container.git
cd claude-code-container
```

Run every `docker compose ...` command below from inside that folder.

## First-time setup

Optional but recommended — enables cloning repos from inside the container
(see [Adding repos](#adding-repos)):

```bash
cp .env.example .env
# edit .env and set GH_TOKEN to a GitHub personal access token
# (fine-grained with Contents read/write, or classic with the `repo` scope)
```

`.env` goes in the project root, next to `docker-compose.yml` — that's the
only place Compose looks for it. It's already in `.gitignore`.

```bash
docker compose up -d --build
```

Claude Code's Remote Control requires a **full interactive OAuth login** —
API keys and `claude setup-token` don't work for it, so this one step can't
be automated. Do it once, either from the host:

```bash
docker exec -it claude-dev sudo -u dev claude
# inside: run /login, finish the browser OAuth flow, accept workspace trust, then exit
```

or from a browser, if you set `WEB_TOKEN` in `.env` — open
`http://<host>:7681`, sign in with username `dev` and `WEB_TOKEN` as the
password, then run `claude` and `/login` the same way (see [Browser
terminal](#browser-terminal)).

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

Open `http://<host>:8811` (bound to `127.0.0.1` in the compose file on
purpose — put it behind Caddy/Tailscale rather than exposing it directly).
It lists every repo's session status and a QR code for pairing the Claude
mobile app. The URL is also shown as a link for connecting from a desktop
browser or the Claude desktop app — both share the same session list since
it's tied to your account, not the device.

From here you can also start/restart/stop a repo's Remote Control session,
clone a new repo (equivalent to `clone-repo` — no shell needed), and, if
the browser terminal is enabled, list/create/close its `tmux` sessions
(see [Browser terminal](#browser-terminal) below). Because it can do all
that, it requires the same `WEB_TOKEN` login as the terminal (HTTP Basic
Auth, username `dev`) whenever one is set. Leaving `WEB_TOKEN` unset
disables the terminal *and* leaves the dashboard unauthenticated — at
that point it's only as protected as the `127.0.0.1` binding actually is
(see SETUP.md's notes on that binding for the Docker Desktop caveat), so
setting a token is worth doing even if you don't plan to use the terminal
itself.

## Browser terminal

Optional — set `WEB_TOKEN` in `.env` (letters, digits, `-`, `_` only) and
restart to enable a full interactive terminal at `http://<host>:7681`, as
an alternative to `docker exec`. The same token also becomes the [web
dashboard](#web-dashboard)'s login, since it can start/stop sessions and
clone repos, not just view them. `WEB_TOKEN` is only the password half of
a basic-auth login — the username is always `dev` (fixed, not set via
`.env`); when the browser prompts, put `dev` in the username field and
`WEB_TOKEN`'s value in the password field. (Formerly `TTYD_TOKEN` — that
name still works, with a deprecation warning, but rename it in `.env`
when convenient.)

**This is a real shell as `dev`** — the same access any Claude Code
session already has (sudo apt-get, whatever `GH_TOKEN` grants, etc.), not
scoped to anything in particular. `WEB_TOKEN` is the only thing gating
it, so treat it like a real password. Each session is backed by `tmux`,
which is a separate process the browser connection doesn't own — so
closing the tab never loses anything, and multiple sessions (and multiple
people) can be connected concurrently. Opening `http://<host>:7681`
directly attaches you to a single default session (`main`); the dashboard
at `http://<host>:8811` lists and creates named sessions, each with its
own starting folder, and can close them too. Typing `exit` at the shell
prompt (not inside `claude` itself) ends a session for good instead of
just detaching from it. There's no per-session access control — anyone
with `WEB_TOKEN` can open or close any session, not just ones they
started. Same rule as the dashboard: it's bound to `127.0.0.1`, don't
expose it beyond that — though see [SETUP.md's notes on what that
password does and doesn't protect
against](SETUP.md#browser-terminal-and-dashboard-username-and-what-the-password-doesnt-protect-against)
before relying on it, especially on Docker Desktop.

Leave `WEB_TOKEN` unset to disable it entirely — the dashboard then shows
a note instead of the link (and becomes unauthenticated itself, since it
has no login of its own), and `docker exec -it claude-dev sudo -u dev
bash` still works as always.

## What's preloaded

Every repo session starts with `git`, `python3`, `node`, `curl`, `wget`, and
`shellcheck` already on `PATH`, plus Java via
[SDKMAN](https://sdkman.io/) — JDK 17 and 21 (the two current LTS releases)
and whatever's currently the latest feature release, with 21 set as the
default `java`/`javac`. (Non-LTS Java releases like 18-20 or 22-24 get
pulled from every distributor within a few months of being superseded, so
those specific versions aren't obtainable to preload — LTS + latest is what
actually stays installable.)

Switch JDKs in a given session with SDKMAN directly:

```bash
sdk use java 17.0.20-tem      # this shell only
sdk default java 21.0.12+1.1-tem   # persist as the default
sdk list java                 # see what's installed, and what else you could add
```

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
  dashboard (port 8811) needs exposing, and only to devices you trust.
