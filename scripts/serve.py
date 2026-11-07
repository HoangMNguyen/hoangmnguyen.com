"""Local preview of site/ with the production security headers.

Serves on http://localhost:8000 (an authorized origin for Focus Bank's Google sign-in),
sends the Content-Security-Policy from infra/site/csp.txt, and answers unknown paths with
site/404.html and a 404 status, like the CloudFront distribution does.

Usage: python3 scripts/serve.py [port]
"""
import http.server
import sys
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
CSP_FILE = ROOT / "infra" / "site" / "csp.txt"


def load_csp() -> str:
    directives = [line.strip() for line in CSP_FILE.read_text().splitlines() if line.strip()]
    # Plain-HTTP localhost would be broken by upgrading subresources to HTTPS.
    directives = [d for d in directives if d != "upgrade-insecure-requests"]
    return "; ".join(directives)


class Handler(http.server.SimpleHTTPRequestHandler):
    csp = load_csp()

    def end_headers(self):
        self.send_header("Content-Security-Policy", self.csp)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_error(self, code, message=None, explain=None):
        page = SITE / "404.html"
        if code == 404 and page.exists():
            body = page.read_bytes()
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            return
        super().send_error(code, message, explain)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), partial(Handler, directory=str(SITE)))
    print(f"Serving {SITE} on http://localhost:{port}")
    server.serve_forever()
