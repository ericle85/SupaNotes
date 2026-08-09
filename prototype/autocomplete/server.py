from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import numpy as np
from pipeline import pipeline

class PipelineHandler(BaseHTTPRequestHandler):
    def do_POST(self):
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
    server.serve_forever()
