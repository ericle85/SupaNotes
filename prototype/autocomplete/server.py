from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import numpy as np
from pipeline import pipeline
from math_engine.engine import do_autosuggestion


class PipelineHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/suggest":
            self._handle_suggest()
        else:
            self._handle_full_pipeline()

    def _handle_suggest(self):
        try:
            length = int(self.headers["Content-Length"])
            body = json.loads(self.rfile.read(length))
            expression = body.get("expression", "")
            result = do_autosuggestion(expression)
            response = json.dumps({"result": result}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response)
        except Exception as e:
            error = json.dumps({"error": str(e)}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error)

    def _handle_full_pipeline(self):
        try:
            length = int(self.headers["Content-Length"])
            raw = json.loads(self.rfile.read(length))
            strokes = [np.array(s) for s in raw]
            result = pipeline(strokes)
            response = json.dumps({"result": result}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response)
        except Exception as e:
            error = json.dumps({"error": str(e)}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error)

    def log_message(self, format, *args):
        print(f"[Server] {args[0]}")


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 5555), PipelineHandler)
    print("[Server] Listening on 0.0.0.0:5555")
    print("[Server] POST /suggest  — math engine only (expression string)")
    print("[Server] POST /         — full pipeline (raw strokes)")
    server.serve_forever()
