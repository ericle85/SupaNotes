#!/usr/bin/env python3
"""
Vision debug server — receives page images from the iPad and shows them in the browser.
Run: python3 vision_server.py
Open: http://localhost:8765

lsof -ti :8765 | xargs kill -9
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
import os, time

PORT = 8765
IMAGE_PATH = "/tmp/supanotes_vision_latest.jpg"

HTML = """<!DOCTYPE html>
<html>
<head>
  <title>SupaNotes Vision</title>
  <style>
    body {{ margin: 0; background: #1a1a1a; display: flex; flex-direction: column;
           align-items: center; justify-content: center; min-height: 100vh; }}
    img  {{ max-height: 95vh; max-width: 95vw; border: 1px solid #444; }}
    p    {{ color: #888; font-family: monospace; font-size: 12px; margin: 8px 0 0; }}
  </style>
  <meta http-equiv="refresh" content="1">
</head>
<body>
  <img src="/latest.jpg?t={ts}" alt="page">
  <p>Last updated: {ts}</p>
</body>
</html>
"""

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence access log

    def do_POST(self):
        if self.path == "/vision":
            length = int(self.headers.get("Content-Length", 0))
            data = self.rfile.read(length)
            with open(IMAGE_PATH, "wb") as f:
                f.write(data)
            print(f"[{time.strftime('%H:%M:%S')}] received {len(data)//1024}KB")
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path.startswith("/latest.jpg"):
            if os.path.exists(IMAGE_PATH):
                with open(IMAGE_PATH, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", len(data))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        elif self.path == "/" or self.path == "/index.html":
            ts = time.strftime("%Y-%m-%d %H:%M:%S")
            html = HTML.format(ts=ts).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", len(html))
            self.end_headers()
            self.wfile.write(html)
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Vision server on http://0.0.0.0:{PORT}")
    print(f"Open http://localhost:{PORT} in your browser")
    server.serve_forever()
