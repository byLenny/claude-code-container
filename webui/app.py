"""
Small dashboard for the claude-dev container.

- Talks to supervisord's XML-RPC interface to list every `claude-<repo>`
  program and its live status.
- Tails each program's log file looking for the Remote Control session
  URL that `claude remote-control` prints on startup.
- Renders a QR code for that URL server-side (Claude Code doesn't draw
  an ASCII QR code in a headless/non-TTY terminal, so we make our own
  from the same URL it prints).
"""
import io
import os
import re
import xmlrpc.client
from pathlib import Path

import qrcode
from flask import Flask, Response, render_template

app = Flask(__name__)

SUPERVISOR_RPC = "http://127.0.0.1:9001/RPC2"
LOG_DIR = Path("/var/log/claude-sessions")

# claude remote-control prints a claude.ai/code session link on startup
URL_RE = re.compile(r"https://claude\.ai/code/\S+")


def get_supervisor_processes():
    try:
        server = xmlrpc.client.ServerProxy(SUPERVISOR_RPC)
        return server.supervisor.getAllProcessInfo()
    except Exception:  # noqa: BLE001 -- any RPC failure should just show an empty list
        return []


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
        "index.html", sessions=sessions, terminal_enabled=terminal_enabled
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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
