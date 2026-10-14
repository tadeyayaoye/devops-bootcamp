"""Métriques Prometheus (méthode RED : Rate, Errors, Duration) + middleware d'observabilité.

Points clés vus au module 09 :
- un *Counter* ne fait que monter (on l'exploite avec rate()/increase()) ;
- un *Histogram* compte les observations dans des « buckets » → histogram_quantile() ;
- le label `route` contient le TEMPLATE de la route (/api/tasks/{task_id}) et jamais l'URL brute
  (/api/tasks/42) : sinon chaque id créerait une nouvelle série → explosion de cardinalité.
"""
from __future__ import annotations

import asyncio
import logging
import random
import time
from dataclasses import dataclass

from fastapi import Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from starlette.routing import Match

logger = logging.getLogger("taskapi.access")

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Nombre total de requêtes HTTP traitées",
    ["method", "route", "status"],
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Durée de traitement des requêtes HTTP",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
HTTP_IN_PROGRESS = Gauge("http_requests_in_progress", "Requêtes HTTP en cours", ["method"])
TASKS_CREATED = Counter("taskapi_tasks_created_total", "Nombre de tâches créées")
BUILD_INFO = Gauge("taskapi_build_info", "Informations de build (valeur toujours 1)", ["version", "env"])

# Les sondes et le scrape ne doivent pas polluer les logs d'accès
QUIET_PATHS = {"/metrics", "/healthz", "/readyz"}


@dataclass
class ChaosState:
    error_rate: float = 0.0
    latency_ms: int = 0


def route_template(request: Request) -> str:
    route = request.scope.get("route")
    if route is not None and hasattr(route, "path"):
        return route.path
    for candidate in request.app.router.routes:
        match, _ = candidate.matches(request.scope)
        if match == Match.FULL and hasattr(candidate, "path"):
            return candidate.path
    return "unmatched"  # 404 : un seul label pour toutes les URL inconnues


async def observability_middleware(request: Request, call_next):
    start = time.perf_counter()
    method = request.method
    status = 500
    HTTP_IN_PROGRESS.labels(method).inc()
    try:
        chaos: ChaosState = request.app.state.chaos
        if request.app.state.settings.chaos_enabled and request.url.path.startswith("/api/"):
            if chaos.latency_ms:
                await asyncio.sleep(chaos.latency_ms / 1000)
            if chaos.error_rate and random.random() < chaos.error_rate:
                logger.error("erreur injectée par le chaos", extra={"path": request.url.path})
                response: Response = JSONResponse({"detail": "chaos: erreur injectée"}, status_code=500)
                status = response.status_code
                return response
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        HTTP_IN_PROGRESS.labels(method).dec()
        elapsed = time.perf_counter() - start
        route = route_template(request)
        if route != "/metrics":
            HTTP_REQUESTS.labels(method, route, str(status)).inc()
            HTTP_LATENCY.labels(method, route).observe(elapsed)
        if request.url.path not in QUIET_PATHS:
            level = logging.WARNING if status >= 500 else logging.INFO
            logger.log(
                level,
                "%s %s %s",
                method,
                request.url.path,
                status,
                extra={
                    "method": method,
                    "path": request.url.path,
                    "route": route,
                    "status": status,
                    "duration_ms": round(elapsed * 1000, 2),
                },
            )


def metrics_response() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
