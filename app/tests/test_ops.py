def test_root(client):
    body = client.get("/").json()
    assert body["service"] == "taskapi"
    assert body["env"] == "test"


def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_readyz_ok(client):
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_readyz_ko_quand_la_base_ne_repond_pas(client, monkeypatch):
    def boom():
        raise RuntimeError("connexion refusée")

    monkeypatch.setattr(client.app.state.db, "ping", boom)
    resp = client.get("/readyz")
    assert resp.status_code == 503
    assert "connexion refusée" in resp.json()["reason"]


def test_version(client):
    assert client.get("/version").json() == {"version": "9.9.9-test", "env": "test"}


def test_metrics_expose_les_series_red(client):
    client.get("/api/tasks")
    client.get("/api/tasks/12345")  # 404
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert "http_request_duration_seconds_bucket" in text
    # le label route contient le template, pas l'id
    assert 'route="/api/tasks/{task_id}"' in text
    assert "/api/tasks/12345" not in text
    assert 'taskapi_build_info{version="9.9.9-test",env="test"} 1.0' in text


def test_url_inconnue_regroupee_sous_un_seul_label(client):
    client.get("/n-existe-pas-1")
    client.get("/n-existe-pas-2")
    text = client.get("/metrics").text
    assert 'route="unmatched"' in text
    assert "n-existe-pas" not in text
