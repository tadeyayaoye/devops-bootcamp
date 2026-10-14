"""Récepteur d'alertes de labo : affiche dans ses logs chaque notification d'Alertmanager.
En entreprise, ce serait Slack, Teams, PagerDuty, Opsgenie, un e-mail…
    kubectl -n monitoring logs -f deploy/alert-sink
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length) or b"{}")
        for alert in payload.get("alerts", []):
            labels, annotations = alert.get("labels", {}), alert.get("annotations", {})
            icon = "🔥" if alert.get("status") == "firing" else "✅"
            print(
                f"{icon} [{alert.get('status', '?').upper()}] {labels.get('alertname')} "
                f"severity={labels.get('severity', '-')} namespace={labels.get('namespace', '-')} "
                f"| {annotations.get('summary', annotations.get('description', ''))}",
                flush=True,
            )
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):  # pas de log d'accès
        pass


if __name__ == "__main__":
    print("alert-sink à l'écoute sur :8080", flush=True)
    HTTPServer(("", 8080), Handler).serve_forever()
