#!/usr/bin/env python3
import http.server
import socketserver
import json
import sys

PORT = 11434

class OllamaMockHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/version":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"version": "0.5.1"}).encode("utf-8"))
        elif self.path == "/api/tags":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            response = {
                "models": [
                    {"name": "llama3.1:latest", "model": "llama3.1:latest", "size": 4661224676}
                ]
            }
            self.wfile.write(json.dumps(response).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/generate":
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)
            req = json.loads(post_data.decode("utf-8")) if post_data else {}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "model": req.get("model", "llama3.1"),
                "response": "VERBUNDEN",
                "done": True
            }).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

class ReusableServer(socketserver.TCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    with ReusableServer(("127.0.0.1", PORT), OllamaMockHandler) as httpd:
        print(f"Mock Ollama server listening on port {PORT}", flush=True)
        httpd.serve_forever()
