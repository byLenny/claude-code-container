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

If you haven't already, clone this repo onto the machine that will run the
container:

```bash
git clone https://github.com/byLenny/claude-code-container.git
cd claude-code-container
```

## 2. (Recommended) Create a GitHub token

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

Now put it in `.env`:

```bash
cp .env.example .env
```

Open `.env` in a text editor and set:

```
GH_TOKEN=github_pat_your_token_here
```

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

```bash
docker exec -it claude-dev sudo -u dev claude
```

Inside the prompt that opens:

1. Type `/login` and press Enter.
2. Follow the link it prints, sign in with your Claude/Anthropic account in
   your browser, and approve the login.
3. Back in the terminal, if it asks about trusting the workspace, accept.
4. Type `/exit` (or press `Ctrl+D`) to leave.

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

Open **http://localhost:8080** in a browser on the same machine (it's bound
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
entrypoint prints exactly which of its five startup checks failed.

**I deleted `workspace/<repo>` by mistake — how do I remove its session?**
Remove the repo folder if it's still there, then
`docker exec -it claude-dev rescan-repos` to regenerate sessions from what's
actually in `/workspace` now. The old session's log file is left behind in
`/var/log/claude-sessions/` but stops being reused.

**I want to start over completely.**
`docker compose down -v` removes the container *and* its volumes (including
the saved Claude Code login) — you'll need to redo step 4 afterwards. This
does not touch `./workspace`, which lives on the host.
