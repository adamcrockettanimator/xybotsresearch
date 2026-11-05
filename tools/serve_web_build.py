"""Serve the threaded Godot web export locally with cross-origin isolation."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial
import sys

class IsolatedHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

if __name__ == "__main__":
    web_root = Path(__file__).resolve().parent.parent / "build" / "web"
    handler = partial(IsolatedHandler, directory=str(web_root))
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
