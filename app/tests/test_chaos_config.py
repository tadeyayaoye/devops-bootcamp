from taskapi.config import Settings


def test_chaos_erreurs_injectees(client):
    assert client.put("/chaos", json={"error_rate": 1.0, "latency_ms": 0}).status_code == 200
    resp = client.get("/api/tasks")
    assert resp.status_code == 500
    assert "chaos" in resp.json()["detail"]
    # les endpoints d'exploitation ne sont jamais impactés
    assert client.get("/healthz").status_code == 200


def test_chaos_retour_a_la_normale(client):
    client.put("/chaos", json={"error_rate": 1.0})
    client.put("/chaos", json={"error_rate": 0.0, "latency_ms": 0})
    assert client.get("/api/tasks").status_code == 200
    assert client.get("/chaos").json() == {"error_rate": 0.0, "latency_ms": 0}


def test_chaos_valide_ses_entrees(client):
    assert client.put("/chaos", json={"error_rate": 2}).status_code == 422


def test_chaos_desactive_par_defaut(make_client):
    c = make_client()  # chaos_enabled=False
    assert c.get("/chaos").status_code == 404


def test_url_postgres_construite_et_echappee():
    s = Settings(db_host="db", db_user="app", db_password="p@ss/word", db_name="tasks")
    assert s.sqlalchemy_url == "postgresql+psycopg://app:p%40ss%2Fword@db:5432/tasks"


def test_database_url_prioritaire():
    s = Settings(database_url="sqlite:///x.db", db_host="ignoré")
    assert s.sqlalchemy_url == "sqlite:///x.db"
