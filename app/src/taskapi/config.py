"""Configuration « 12-factor » : tout vient de l'environnement, rien n'est codé en dur.

Ordre de priorité (pydantic-settings) : arguments explicites > variables d'environnement
> fichier .env > fichiers de secrets (/run/secrets/<nom_du_champ>) > valeurs par défaut.
"""
from __future__ import annotations

import os
from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict

SECRETS_DIR = "/run/secrets"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
        # Docker Compose (secrets:) et Kubernetes (Secret monté en volume) déposent des fichiers ici
        secrets_dir=SECRETS_DIR if os.path.isdir(SECRETS_DIR) else None,
    )

    app_name: str = "taskapi"
    app_env: str = "local"
    app_version: str = "0.1.0-dev"
    log_level: str = "INFO"

    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "taskapi"
    db_user: str = "taskapi"
    db_password: str = "taskapi"

    otel_enabled: bool = False
    otel_exporter_otlp_endpoint: str = "http://localhost:4318"

    chaos_enabled: bool = False

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        # quote_plus : un mot de passe contenant @, / ou : casserait l'URL sinon
        return (
            f"postgresql+psycopg://{quote_plus(self.db_user)}:{quote_plus(self.db_password)}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
