# taskapi — l'application fil rouge

Petite API REST de gestion de tâches, volontairement simple côté métier mais **complète côté exploitation** : c'est elle qui traverse toute la chaîne du bootcamp.

| Fonction | Où | Utilisée au module |
|---|---|---|
| CRUD `/api/tasks` (FastAPI + SQLAlchemy) | `src/taskapi/routes.py` | tous |
| Base Postgres **ou** SQLite (tests / local) | `src/taskapi/db.py`, `config.py` | 01, 02, 05 |
| Configuration 12-factor par variables d'environnement (+ secrets fichiers `/run/secrets`) | `config.py` | 01, 02, 08 |
| Liveness `/healthz`, readiness `/readyz` (ping DB) | `routes.py` | 01, 02 |
| Métriques Prometheus `/metrics` (RED : rate, errors, duration) | `metrics.py` | 09 |
| Logs JSON structurés avec `trace_id` | `logging_setup.py` | 10 |
| Traces OpenTelemetry (OTLP HTTP) | `telemetry.py` | 10 |
| Chaos : taux d'erreur et latence injectables `/chaos` | `routes.py`, `metrics.py` | 09, 10, 11 |
| Tests pytest + couverture | `tests/` | 00, 06, 07 |

## Lancer en local (module 00)

```bash
cd app
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
ruff check .                      # lint
pytest --cov                      # tests + couverture
DATABASE_URL=sqlite:///./taskapi.db CHAOS_ENABLED=true \
  PYTHONPATH=src uvicorn taskapi.main:create_app --factory --reload
# → http://localhost:8000/docs
```

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `APP_ENV` | `local` | nom de l'environnement (label des métriques, logs) |
| `APP_VERSION` | `0.1.0-dev` | version exposée par `/version` (injectée au build) |
| `LOG_LEVEL` | `INFO` | niveau de log |
| `DATABASE_URL` | — | URL SQLAlchemy complète ; si absente, construite depuis `DB_*` |
| `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` | `localhost` / `5432` / `taskapi` / `taskapi` / `taskapi` | connexion Postgres |
| `OTEL_ENABLED` | `false` | active l'export des traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | collecteur OTLP (Alloy) |
| `CHAOS_ENABLED` | `false` | active les endpoints `/chaos` |

Un fichier nommé comme la variable en minuscules dans `/run/secrets/` (ex. `/run/secrets/db_password`) est aussi lu : c'est ainsi que fonctionnent les *secrets* Docker Compose et les Secrets Kubernetes montés en volume.

## Endpoints

| Méthode | Chemin | Description |
|---|---|---|
| GET | `/` | infos service |
| GET | `/healthz` | liveness : le process répond (aucune dépendance) |
| GET | `/readyz` | readiness : la base répond (`SELECT 1`), sinon 503 |
| GET | `/version` | version + environnement |
| GET | `/metrics` | métriques Prometheus |
| GET/POST | `/api/tasks` | lister (`?done=true&limit=&offset=`) / créer |
| GET/PATCH/DELETE | `/api/tasks/{id}` | lire / modifier / supprimer |
| GET/PUT | `/chaos` | lire / régler `{"error_rate": 0.3, "latency_ms": 500}` (si `CHAOS_ENABLED=true`) |
