"""Serve the built Flutter preview and local API through one LAN address.

Use synthetic stories only: this development server has no user authentication.
"""

from __future__ import annotations

import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: object, directory: str, api_url: str, **kwargs: object) -> None:
        self.api_url = api_url.rstrip("/")
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        if self.path.startswith("/api/v1/"):
            self._proxy("GET")
        else:
            super().do_GET()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self) -> None:
        self._proxy("POST")

    def do_PATCH(self) -> None:
        self._proxy("PATCH")

    def _proxy(self, method: str) -> None:
        if not self.path.startswith("/api/v1/"):
            self.send_error(404)
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if content_length < 0 or content_length > 1_000_000:
            self.send_error(413)
            return
        body = self.rfile.read(content_length) if content_length else None
        request = Request(
            f"{self.api_url}{self.path}",
            data=body,
            headers={"Content-Type": "application/json"},
            method=method,
        )
        try:
            with urlopen(request, timeout=70) as response:
                self._send_api_response(
                    response.status,
                    response.read(),
                    response.headers.get("Content-Type", "application/json"),
                )
        except HTTPError as response:
            self._send_api_response(
                response.code,
                response.read(),
                response.headers.get("Content-Type", "application/json"),
            )
        except (URLError, TimeoutError, OSError):
            self._send_api_response(
                502,
                json.dumps({"detail": "The local API is unavailable. Please try again."}).encode(),
                "application/json",
            )

    def _send_api_response(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--api-url", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    build_dir = Path(__file__).resolve().parents[1] / "mobile" / "build" / "web"
    if not (build_dir / "index.html").is_file():
        parser.error("Build the Flutter web app before starting this preview.")
    handler = partial(PreviewHandler, directory=str(build_dir), api_url=args.api_url)
    with ThreadingHTTPServer((args.host, args.port), handler) as server:
        print(f"FinPilot preview: http://{args.host}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
