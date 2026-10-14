"""Logs JSON sur stdout : un événement = une ligne = un objet JSON.

Pourquoi ? Dans un conteneur, on écrit sur stdout et c'est la plateforme (kubelet, agent
Alloy, Loki…) qui collecte. Le JSON permet ensuite de filtrer finement (LogQL `| json`) et
le champ `trace_id` permet de sauter d'un log à la trace correspondante dans Grafana.
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime

from opentelemetry import trace

EXTRA_FIELDS = ("method", "path", "route", "status", "duration_ms", "attempt", "error", "version", "env")


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        span_ctx = trace.get_current_span().get_span_context()
        if span_ctx.is_valid:
            payload["trace_id"] = format(span_ctx.trace_id, "032x")
            payload["span_id"] = format(span_ctx.span_id, "016x")
        for key in EXTRA_FIELDS:
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level.upper())
    # uvicorn a ses propres handlers : on les fait passer par notre format JSON
    for name in ("uvicorn", "uvicorn.error"):
        lg = logging.getLogger(name)
        lg.handlers[:] = []
        lg.propagate = True
    logging.getLogger("uvicorn.access").disabled = True  # remplacé par notre log d'accès
