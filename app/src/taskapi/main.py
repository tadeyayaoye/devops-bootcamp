"""Point d'entrée : application factory.

Lancement : uvicorn taskapi.main:create_app --factory --host 0.0.0.0 --port 8000
(une *factory* évite de créer l'application — et de se connecter à la base — au simple import
du module, ce qui rend les tests plus simples.)
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import Settings, get_settings
from .db import Database
from .logging_setup import configure_logging
from .metrics import BUILD_INFO, ChaosState, observability_middleware
from .routes import router
from .telemetry import setup_tracing

logger = logging.getLogger("taskapi")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    db = Database(settings.sqlalchemy_url)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        db.create_schema()
        logger.info("démarrage", extra={"version": settings.app_version, "env": settings.app_env})
        yield
        # Arrêt propre : déclenché par SIGTERM (docker stop, suppression de pod…)
        logger.info("arrêt", extra={"version": settings.app_version, "env": settings.app_env})
        db.dispose()

    app = FastAPI(title="taskapi", version=settings.app_version, lifespan=lifespan)
    app.state.settings = settings
    app.state.db = db
    app.state.chaos = ChaosState()

    BUILD_INFO.labels(settings.app_version, settings.app_env).set(1)
    app.middleware("http")(observability_middleware)
    app.include_router(router)
    setup_tracing(app, settings, db.engine)  # après le middleware : le span englobe nos logs
    return app
