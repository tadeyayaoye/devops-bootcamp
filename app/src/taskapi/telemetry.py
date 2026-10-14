"""Traces distribuées avec OpenTelemetry (module 10).

L'application ne connaît que le protocole standard OTLP : elle envoie ses spans à un
collecteur (Grafana Alloy dans le cluster) qui les route vers Tempo. Changer de backend
(Jaeger, Datadog, Honeycomb…) ne demande donc aucune modification du code.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI
from sqlalchemy.engine import Engine

from .config import Settings

logger = logging.getLogger("taskapi.telemetry")


def setup_tracing(app: FastAPI, settings: Settings, engine: Engine) -> None:
    if not settings.otel_enabled:
        return

    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    resource = Resource.create(
        {
            "service.name": settings.app_name,
            "service.version": settings.app_version,
            "deployment.environment": settings.app_env,
        }
    )
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=f"{settings.otel_exporter_otlp_endpoint.rstrip('/')}/v1/traces")
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    FastAPIInstrumentor.instrument_app(app, tracer_provider=provider, excluded_urls="healthz,readyz,metrics")
    SQLAlchemyInstrumentor().instrument(engine=engine, tracer_provider=provider)
    logger.info("traces OpenTelemetry activées", extra={"env": settings.app_env})
