"""
Small dashboard for the claude-dev container.

- Talks to supervisord's XML-RPC interface to list every `claude-<repo>`
  program and its live status, and to start/stop/restart them.
- Tails each program's log file looking for the Remote Control session
  URL that `claude remote-control` prints on startup.
- Renders a QR code for that URL server-side (Claude Code doesn't draw
  an ASCII QR code in a headless/non-TTY terminal, so we make our own
  from the same URL it prints).
- Lists and manages the tmux sessions behind the browser terminal
  (:7681) -- creating one here starts it headless (detached, no client
  attached yet); opening it in the browser attaches to whatever's
  already running, same as reconnecting to one you started there.
- Shells out to clone-repo/gen-supervisor-repos to add new repo
  sessions. This process already runs as 'dev' (see supervisord.conf),
  same user those scripts expect when invoked directly (without sudo).
- Requires the same TTYD_TOKEN as the browser terminal (HTTP Basic Auth,
  username 'dev') whenever one is set -- this page can clone repos and
  start/stop sessions, not just view them, so it needs the same gate the
  terminal already has. Matches the terminal's own opt-out: if
  TTYD_TOKEN is unset, this stays unauthenticated too, same as today.
"""

import hmac
import io
import os
import re
import secrets
import subprocess
import xmlrpc.client
from pathlib import Path

import qrcode
from flask import Flask, Response, redirect, render_template, request, url_for

app = Flask(__name__)


@app.before_request
def require_auth():
    token = os.environ.get("TTYD_TOKEN")
    if not token:
        return None
    auth = request.authorization
    if not auth or auth.username != "dev" or not hmac.compare_digest(auth.password or "", token):
        return Response(
            "Authentication required.",
            401,
            {"WWW-Authenticate": 'Basic realm="claude-dev dashboard"'},
        )
    return None

SUPERVISOR_RPC = "http://127.0.0.1:9001/RPC2"
LOG_DIR = Path("/var/log/claude-sessions")
WORKSPACE = Path("/workspace")
SCRIPTS_DIR = Path("/opt/scripts")

# claude remote-control prints a claude.ai/code session link on startup
URL_RE = re.compile(r"https://claude\.ai/code/\S+")

# tmux session names double as a `-t` target, where ':' and '.' are
# session:window.pane separators -- keep names unambiguous. Matches the
# same restriction terminal-attach.sh applies on the ttyd side.
SESSION_NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")

# Target folder name for a cloned repo -- matches clone-repo.sh's own
# check. Checked here too so a bad request never even reaches the script.
REPO_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def get_supervisor_processes():
    try:
        server = xmlrpc.client.ServerProxy(SUPERVISOR_RPC)
        return server.supervisor.getAllProcessInfo()
    except Exception:  # noqa: BLE001 -- any RPC failure should just show an empty list
        return []


def supervisor_call(method: str, *args) -> bool:
    """Best-effort start/stop/restart -- the dashboard just re-polls real
    status afterwards, so a fault (already stopped, already running) isn't
    worth surfacing as an error."""
    try:
        server = xmlrpc.client.ServerProxy(SUPERVISOR_RPC)
        getattr(server.supervisor, method)(*args)
        return True
    except Exception:  # noqa: BLE001 -- see docstring
        return False


def find_session_url(repo: str) -> str | None:
    log_file = LOG_DIR / f"{repo}.log"
    if not log_file.exists():
        return None
    try:
        # session URL is printed once near startup; scan from the end
        # backwards is unnecessary for a small log, just read whole file
        text = log_file.read_text(errors="ignore")
    except OSError:
        return None
    matches = URL_RE.findall(text)
    return matches[-1] if matches else None


def list_workspace_repos() -> list[str]:
    if not WORKSPACE.is_dir():
        return []
    return sorted(
        p.name
        for p in WORKSPACE.iterdir()
        if p.is_dir() and p.name != ".devtools" and (p / ".git").is_dir()
    )


def list_tmux_sessions() -> list[dict]:
    try:
        proc = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if proc.returncode != 0:
        return []  # no tmux server running yet == no sessions
    sessions = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        name, windows, attached = parts
        sessions.append({"name": name, "windows": windows, "attached": attached == "1"})
    sessions.sort(key=lambda s: s["name"])
    return sessions


def resolve_session_folder(raw: str) -> str:
    """Folder a new tmux session should start in. Not a security boundary
    (this is already a full 'dev' shell), just guards against a typo'd
    path silently landing somewhere confusing -- falls back to /workspace
    itself if the input is empty, escapes /workspace, or doesn't exist."""
    raw = (raw or "").strip().lstrip("/")
    candidate = (WORKSPACE / raw) if raw else WORKSPACE
    try:
        candidate = candidate.resolve()
        candidate.relative_to(WORKSPACE.resolve())
    except (OSError, ValueError):
        return str(WORKSPACE)
    return str(candidate) if candidate.is_dir() else str(WORKSPACE)


@app.route("/")
def index():
    sessions = []
    for proc in get_supervisor_processes():
        name = proc.get("name", "")
        if not name.startswith("claude-"):
            continue
        repo = name[len("claude-"):]
        url = find_session_url(repo)
        sessions.append(
            {
                "repo": repo,
                "status": proc.get("statename", "UNKNOWN"),
                "url": url,
                "has_qr": url is not None,
            }
        )
    sessions.sort(key=lambda s: s["repo"])
    terminal_enabled = bool(os.environ.get("TTYD_TOKEN"))
    return render_template(
        "index.html",
        sessions=sessions,
        terminal_enabled=terminal_enabled,
        terminal_sessions=list_tmux_sessions() if terminal_enabled else [],
        repo_names=list_workspace_repos(),
    )


@app.route("/qr/<repo>.png")
def qr_code(repo: str):
    url = find_session_url(repo)
    if not url:
        return Response(status=404)
    img = qrcode.make(url, box_size=8, border=2)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return Response(buf.read(), mimetype="image/png")


@app.route("/session/<repo>/<action>", methods=["POST"])
def control_session(repo: str, action: str):
    name = f"claude-{repo}"
    if action == "stop":
        supervisor_call("stopProcess", name)
    elif action == "start":
        supervisor_call("startProcess", name)
    elif action == "restart":
        supervisor_call("stopProcess", name)
        supervisor_call("startProcess", name)
    return redirect(url_for("index"))


@app.route("/clone", methods=["POST"])
def clone():
    source = request.form.get("source", "").strip()
    name = request.form.get("name", "").strip()
    # clone-repo.sh re-checks both of these itself, but reject obviously
    # bad input here too rather than spawning a process that's just
    # going to fail -- see clone-repo.sh for why these checks exist.
    valid_source = source and not source.startswith("-")
    valid_name = not name or REPO_NAME_RE.match(name)
    if valid_source and valid_name:
        cmd = [str(SCRIPTS_DIR / "clone-repo.sh"), source]
        if name:
            cmd.append(name)
        # Fire-and-forget: a git clone can take a while, and this request
        # shouldn't block the whole (single-worker) dashboard while it
        # runs. The new session shows up once gen-supervisor-repos.sh
        # (called by clone-repo.sh itself) registers it -- the page
        # auto-refreshes every 15s already.
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return redirect(url_for("index"))


@app.route("/terminal/new", methods=["POST"])
def new_terminal():
    name = re.sub(r"[^A-Za-z0-9_-]", "", request.form.get("name", ""))
    if not name:
        name = f"session-{secrets.token_hex(3)}"
    folder = resolve_session_folder(request.form.get("folder", ""))
    subprocess.run(["tmux", "new-session", "-d", "-s", name, "-c", folder], check=False)
    return redirect(url_for("index"))


@app.route("/terminal/<name>/close", methods=["POST"])
def close_terminal(name: str):
    if SESSION_NAME_RE.match(name):
        subprocess.run(["tmux", "kill-session", "-t", name], check=False)
    return redirect(url_for("index"))


if __name__ == "__main__":
    # threaded=True so a slow /clone (a git clone in flight) doesn't
    # block the read-only "/" polling every other open tab is doing.
    app.run(host="0.0.0.0", port=8080, threaded=True)
