"""hello-svc: minimal stub web service with /, /health and /version.

Standard library only, so the image needs no pip install step.
Run locally:  python app/main.py
Healthcheck:  python app/main.py --healthcheck   (exit 0 = healthy)
"""
import json
import logging
import os
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.getenv("APP_VERSION", "dev")
COMMIT = os.getenv("GIT_SHA", "unknown")
PORT = int(os.getenv("PORT", "8080"))


class JsonFormatter(logging.Formatter):
    """One JSON object per log line on stdout, easy to ship to Azure Monitor."""

    def format(self, record):
        entry = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "msg": record.getMessage(),
        }
        entry.update(getattr(record, "extra_fields", {}))
        return json.dumps(entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("hello-svc")
log.addHandler(handler)
log.setLevel(logging.INFO)


class Handler(BaseHTTPRequestHandler):
    server_version = "hello-svc"
    sys_version = ""

    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        start = time.monotonic()
        if self.path == "/health":
            code, body = 200, {"status": "ok"}
        elif self.path == "/version":
            code, body = 200, {"version": VERSION, "commit": COMMIT}
        elif self.path == "/":
            code, body = 200, {"message": "hello from hello-svc", "version": VERSION}
        else:
            code, body = 404, {"error": "not found"}
        self._send(code, body)
        log.info("request", extra={"extra_fields": {
            "method": "GET",
            "path": self.path,
            "status": code,
            "dur_ms": round((time.monotonic() - start) * 1000, 2),
        }})

    def log_message(self, fmt, *args):
        pass  # replaced by the structured log line in do_GET


def healthcheck():
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
            return 0 if r.status == 200 else 1
    except Exception:
        return 1


if __name__ == "__main__":
    if "--healthcheck" in sys.argv:
        sys.exit(healthcheck())
    log.info("starting", extra={"extra_fields": {"port": PORT, "version": VERSION, "commit": COMMIT}})
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()