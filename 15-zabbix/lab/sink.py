"""Récepteur générique de notifications : affiche chaque POST JSON reçu.
    docker compose -f 15-zabbix/lab/compose.yaml logs -f alert-sink
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        try:
            data = json.loads(body or b"{}")
            sev = data.get("severity", "?")
            print(f"📟 [{sev}] {data.get('subject', '')}\n    {data.get('message', '')}".rstrip(), flush=True)
        except ValueError:
            print(f"📟 (non JSON) {body[:500]!r}", flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("alert-sink à l'écoute sur :8080", flush=True)
    HTTPServer(("", 8080), Handler).serve_forever()
