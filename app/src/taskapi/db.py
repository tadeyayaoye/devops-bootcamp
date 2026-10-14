"""Accès base de données (SQLAlchemy 2.x, mode synchrone)."""
from __future__ import annotations

import logging
import time
from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

logger = logging.getLogger("taskapi.db")


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self, url: str) -> None:
        kwargs: dict = {"pool_pre_ping": True}
        if url.startswith("sqlite"):
            kwargs["connect_args"] = {"check_same_thread": False}
            if ":memory:" in url:
                kwargs["poolclass"] = StaticPool
        self.engine: Engine = create_engine(url, **kwargs)
        self.session_factory = sessionmaker(bind=self.engine, autoflush=False, expire_on_commit=False)

    def create_schema(self, retries: int = 10, delay: float = 2.0) -> None:
        """Crée les tables au démarrage, en attendant que la base soit joignable.

        En entreprise on utiliserait des migrations versionnées (Alembic) lancées par un Job
        ou un hook de déploiement, pas un create_all au démarrage de l'application.
        """
        from . import models  # noqa: F401 - enregistre les modèles dans Base.metadata

        for attempt in range(1, retries + 1):
            try:
                Base.metadata.create_all(self.engine)
                return
            except Exception as exc:  # noqa: BLE001
                if attempt == retries:
                    raise
                logger.warning(
                    "base indisponible, nouvelle tentative",
                    extra={"attempt": attempt, "error": str(exc).splitlines()[0]},
                )
                time.sleep(delay)

    def ping(self) -> None:
        with self.engine.connect() as conn:
            conn.execute(text("SELECT 1"))

    def dispose(self) -> None:
        self.engine.dispose()


def get_session(request: Request) -> Iterator[Session]:
    """Dépendance FastAPI : une session par requête, toujours refermée."""
    session: Session = request.app.state.db.session_factory()
    try:
        yield session
    finally:
        session.close()
