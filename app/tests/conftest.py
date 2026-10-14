import pytest
from fastapi.testclient import TestClient

from taskapi.config import Settings
from taskapi.main import create_app


@pytest.fixture
def make_client(tmp_path):
    """Fabrique un client de test avec une base SQLite jetable et des réglages surchargeables."""
    clients = []

    def _make(**overrides) -> TestClient:
        settings = Settings(
            database_url=f"sqlite:///{tmp_path / 'test.db'}",
            app_env="test",
            app_version="9.9.9-test",
            **overrides,
        )
        client = TestClient(create_app(settings))
        client.__enter__()  # déclenche le lifespan (création du schéma)
        clients.append(client)
        return client

    yield _make
    for c in clients:
        c.__exit__(None, None, None)


@pytest.fixture
def client(make_client) -> TestClient:
    return make_client(chaos_enabled=True)
