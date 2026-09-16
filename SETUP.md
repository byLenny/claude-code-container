# Setup guide

A step-by-step walkthrough for getting this container running for the first
time. If you already know Docker, the [README](README.md) is a faster
reference — this doc spells out every step, including the parts that only
happen once.

## What you'll need

- **Docker Desktop** (Windows/Mac) or **Docker Engine + Compose** (Linux),
  installed and running —
  [install instructions](https://docs.docker.com/get-started/get-docker/).
- A **GitHub account** — to log in to `claude.ai/code`, and (optionally) to
  create a token so the container can clone your repos.
- A **Claude account** with access to Claude Code — see
  [Claude Code docs](https://docs.claude.com/en/docs/claude-code/overview) if
  you haven't used it before, or [claude.com/pricing](https://claude.com/pricing)
  if you need a plan that includes it.

## 1. Get the code

`docker-compose.yml` isn't something you copy out on its own — it builds the
image from the `Dockerfile` sitting next to it (`build: .`), and that in turn
needs `entrypoint.sh`, `scripts/`, and `webui/` from this same repo. So clone
the whole repo onto the machine that will actually run the container (a
server, NAS, or your own machine):

```bash
git clone https://github.com/byLenny/claude-code-container.git
cd claude-code-container
```

Wherever that `claude-code-container` folder ends up is where you'll run
every `docker compose ...` command from for the rest of this guide, and
where `.env` and `./workspace` live. It's fine to move the whole folder
later — everything in it is relative — just `cd` there first.

## 2. (Recommended) Create a GitHub token and pick a terminal password

This lets the container clone/push repos you have access to, without you
having to `git clone` on the host yourself every time. Skip this step if you'd
rather always clone repos into `./workspace` manually — everything else still
works.

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
   (this is the same page GitHub's own
   [token documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
   walks through in more detail, if you want the full explanation).
2. Create a **fine-grained token**:
   - Repository access: the repos you want this box to work on (or "All
     repositories" if that's easier for you).
   - Permissions → Repository permissions → **Contents: Read and write**.
   - Set an expiration you're comfortable with — you'll need to refresh the
     token in `.env` when it expires.
3. Copy the token (starts with `github_pat_...`). You won't be able to see it
   again after leaving the page.

(A classic token with the `repo` scope also works, if your org requires
that instead — see
[creating a classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic).)

Now put it in `.env`, in the project root (the same folder as
`docker-compose.yml` — that's the only place Compose reads it from):

```bash
cp .env.example .env
```

Open `.env` in a text editor and set:

```
GH_TOKEN=github_pat_your_token_here
```

While you're in there, also pick a password for the browser terminal
(step 4 uses it for login, but it's a full shell — see [Browser
terminal](README.md#browser-terminal) in the README) — letters, digits,
`-` and `_` only:

```
TTYD_TOKEN=some-password-you-pick
```

Leave `TTYD_TOKEN` blank if you'd rather skip the browser terminal
entirely and always use `docker exec` instead — both work.

### Browser terminal: username, and what the password doesn't protect against

When you sign in at `http://<host>:7681`, the **username is always `dev`**
— it's fixed in the image, not something you set in `.env`. Only the
password (`TTYD_TOKEN`) is yours to choose.

That password is the *only* thing gating a full, unscoped shell (sudo
apt-get, whatever `GH_TOKEN` grants, etc. — see
[Browser terminal](README.md#browser-terminal) in the README), so it's
worth knowing what it doesn't cover:

- **No TLS.** It's plain HTTP Basic Auth, so the username/password go over
  the network in the clear on every request unless you put a reverse proxy
  (Caddy, Tailscale, etc.) in front with HTTPS.
- **No lockout.** There's nothing rate-limiting failed login attempts, so
  treat `TTYD_TOKEN` like a real password, not a PIN — a long random value
  beats something short and memorable. The allowed charset (letters,
  digits, `-`, `_`) also has no room for extra symbols, so length is what
  gives it strength.
- **`127.0.0.1:7681:7681` in `docker-compose.yml` is not a reliable
  substitute for a real password.** It's meant to keep the port off your
  network entirely, and on native Docker Engine (Linux) it does. But on
  **Docker Desktop (Windows/Mac)**, the VM-based port-forwarding proxy does
  not always honor loopback-only bindings — the port can still answer on
  your LAN IP, not just `localhost`. Don't assume `127.0.0.1` in the compose
  file means "only this machine can reach it": verify it yourself from a
  second device (`curl http://<host-LAN-IP>:7681/` — a connection refused
  is what you want; a response means it's reachable from your network) and,
  if it answers, put a firewall rule or a reverse proxy with its own auth in
  front rather than relying on the port binding alone.
- Only one person can be connected at a time (`ttyd --once` closes the
  connection after you disconnect), but the token itself doesn't rotate
  or expire — anyone who has it can connect the moment it's free. And
  because every connection joins the same shared `tmux` session, the
  next person in sees whatever the previous one left on screen or
  running — there's no per-connection isolation.

Once you're signed in at the shell prompt (`dev@claude-dev:~$`), the next
step is signing in to *Claude Code itself* — that's [step 4](#4-log-in-to-claude-code-one-time-only)
below: run `claude`, then `/login` inside it.

`.env` is already in `.gitignore`, so it stays on this machine and won't get
committed.

## 3. Build and start the container

```bash
docker compose up -d --build
```

This builds the image (first run takes a few minutes) and starts it in the
background. Check it came up cleanly:

```bash
docker compose logs -f
```

You should see setup steps like `Checking GitHub authentication` and
`Checking Claude Code authentication` scroll by. Press `Ctrl+C` to stop
following the logs (the container keeps running).

## 4. Log in to Claude Code (one time only)

Claude Code's Remote Control needs a real interactive browser login — this
is the one step that can't be automated, and you only do it once. (Background
on Remote Control itself:
[docs.claude.com/en/docs/claude-code/remote-control](https://docs.claude.com/en/docs/claude-code/remote-control).)

Two ways to do it — pick whichever's easier:

**From the host terminal:**

```bash
docker exec -it claude-dev sudo -u dev claude
```

**From a browser**, if you set `TTYD_TOKEN` in `.env` back in step 2 (add
it now and re-run `docker compose up -d` if you skipped it): open
`http://localhost:7681`, and when the browser's basic-auth prompt appears,
sign in with username `dev` and your `TTYD_TOKEN` as the password. You'll
land in a shell — type `claude` to get the same prompt described below.

Either way, once you're at the `claude` prompt:

1. Type `/login` and press Enter.
2. Follow the link it prints, sign in with your Claude/Anthropic account in
   your browser, and approve the login.
3. Back in the terminal, if it asks about trusting the workspace, accept.
4. Type `/exit` (or press `Ctrl+D`) to leave — if you used the browser
   terminal, closing the tab works too; it closes itself after you
   disconnect either way.

This login is saved in a Docker volume (`claude-config`), so it survives
container restarts and rebuilds — you won't need to repeat this unless you
delete that volume.

Now restart so the container picks up the saved login and starts a session
for every repo already in `./workspace`:

```bash
docker compose restart
```

## 5. Add a repo to work on

**If you set up `GH_TOKEN` in step 2**, do this from your host terminal:

```bash
docker exec -it claude-dev list-repos
docker exec -it claude-dev clone-repo owner/repo-name
```

`list-repos` shows what you have access to; `clone-repo` clones the repo into
`./workspace/<repo-name>` and starts its Claude Code session immediately —
no restart needed.

**Without `GH_TOKEN`**, clone or copy the repo yourself into
`./workspace/<name>` on the host, then run:

```bash
docker exec -it claude-dev rescan-repos
```

Either way, each repo now has its own always-on Claude Code session.

## 6. Connect from the Claude app

Open **http://localhost:8811** in a browser on the same machine (it's bound
to `127.0.0.1` on purpose — see the note in the README if you need to reach
it from another device). You'll see one row per repo with a status and a QR
code.

- **Mobile**: scan the QR code with the Claude mobile app.
- **Desktop/browser**: click the link shown next to the QR code.

Both connect to the same session — pick whichever's convenient.

## You're set up

From here, day-to-day usage is just:

- `docker exec -it claude-dev clone-repo owner/repo` to add another repo.
- Open the dashboard to jump into any session from your phone or desktop.
- `docker exec -it claude-dev add-package <name>` then `install-packages` if
  a repo needs an extra apt package (see the README for details).

Git, Python, Node, curl/wget, shellcheck, and Java (17, 21, and the current
latest, via SDKMAN) are already preloaded in every session — see [What's
preloaded](README.md#whats-preloaded) in the README for details, including
how to switch Java versions.

## Useful links

- [Docker install docs](https://docs.docker.com/get-started/get-docker/)
- [Docker Compose install docs](https://docs.docker.com/compose/install/)
- [Claude Code overview](https://docs.claude.com/en/docs/claude-code/overview)
- [Claude Code Remote Control docs](https://docs.claude.com/en/docs/claude-code/remote-control)
- [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [Create a GitHub token directly](https://github.com/settings/tokens)

## Troubleshooting

**Dashboard shows a repo as `FATAL` or missing a QR code.**
Check its log: `docker exec -it claude-dev tail -50 /var/log/claude-sessions/<repo>.log`.
Most often this means the Claude Code login (step 4) hasn't happened yet.

**`clone-repo` says "gh is not authenticated".**
`GH_TOKEN` in `.env` is missing, empty, or expired. Update `.env` and run
`docker compose up -d` again to recreate the container with the new value.

**Container restarts in a loop after `docker compose up -d --build`.**
Run `docker compose logs` (without `-f`) and read the last screenful — the
entrypoint prints exactly which of its six startup checks failed.

**`http://localhost:7681` doesn't load, or asks for a password you don't have.**
`TTYD_TOKEN` isn't set in `.env` (the browser terminal is off by default —
see step 2), or the container hasn't been restarted since you set it. The
password is whatever you set `TTYD_TOKEN` to; the username is `dev`. See
[Browser terminal: username, and what the password doesn't protect
against](#browser-terminal-username-and-what-the-password-doesnt-protect-against)
above for what that password does and doesn't secure.

**I deleted `workspace/<repo>` by mistake — how do I remove its session?**
Remove the repo folder if it's still there, then
`docker exec -it claude-dev rescan-repos` to regenerate sessions from what's
actually in `/workspace` now. The old session's log file is left behind in
`/var/log/claude-sessions/` but stops being reused.

**I want to start over completely.**
`docker compose down -v` removes the container *and* its volumes (including
the saved Claude Code login) — you'll need to redo step 4 afterwards. This
does not touch `./workspace`, which lives on the host.
