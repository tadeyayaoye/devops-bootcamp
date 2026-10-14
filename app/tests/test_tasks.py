def create(client, title="écrire le Dockerfile", **extra):
    resp = client.post("/api/tasks", json={"title": title, **extra})
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_creer_puis_lire(client):
    task = create(client, description="multi-stage, non-root")
    assert task["id"] > 0
    assert task["done"] is False
    assert client.get(f"/api/tasks/{task['id']}").json()["title"] == "écrire le Dockerfile"


def test_lister_et_filtrer(client):
    a = create(client, "a")
    create(client, "b")
    client.patch(f"/api/tasks/{a['id']}", json={"done": True})

    assert len(client.get("/api/tasks").json()) == 2
    done = client.get("/api/tasks", params={"done": True}).json()
    assert [t["title"] for t in done] == ["a"]


def test_pagination(client):
    for i in range(5):
        create(client, f"t{i}")
    page = client.get("/api/tasks", params={"limit": 2, "offset": 2}).json()
    assert [t["title"] for t in page] == ["t2", "t3"]


def test_modifier(client):
    task = create(client)
    resp = client.patch(f"/api/tasks/{task['id']}", json={"title": "nouveau titre", "done": True})
    assert resp.status_code == 200
    assert resp.json()["title"] == "nouveau titre"
    assert resp.json()["done"] is True


def test_supprimer(client):
    task = create(client)
    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_404(client):
    resp = client.get("/api/tasks/999")
    assert resp.status_code == 404
    assert "introuvable" in resp.json()["detail"]


def test_validation(client):
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422
    assert client.post("/api/tasks", json={}).status_code == 422
    assert client.get("/api/tasks", params={"limit": 1000}).status_code == 422
