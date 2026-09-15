#!/usr/bin/env python3
"""Serve the local Tchap build on the LAN with permissive asset CORS."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


class CorsRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8082
directory = Path(sys.argv[2] if len(sys.argv) > 2 else "dist").resolve()
handler = lambda *args, **kwargs: CorsRequestHandler(  # noqa: E731
    *args, directory=str(directory), **kwargs
)
ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()