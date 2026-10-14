# Module 01 — Labs Docker

> ⏱ ~3 h · Tout se passe dans `~/devops-bootcamp`.

---

## Lab 1.1 — Un conteneur n'est qu'un processus (≈ 25 min)

```bash
docker run -d --name sleeper alpine sleep 3600
docker top sleeper                      # le process vu par Docker
ps -ef | grep "sleep 3600"              # le MÊME process, vu depuis l'hôte, avec un autre PID
PID=$(docker inspect -f '{{.State.Pid}}' sleeper)
sudo ls -l /proc/$PID/ns                # ses namespaces
lsns -p $PID 2>/dev/null || sudo lsns -p $PID
docker exec sleeper ps                  # dans le conteneur : sleep est PID 1
docker exec sleeper hostname            # namespace UTS
cat /sys/fs/cgroup/system.slice/docker-$(docker inspect -f '{{.Id}}' sleeper).scope/memory.max
docker rm -f sleeper
```

**cgroups en action — OOM kill :**

```bash
docker run --name oom --memory 64m python:3.12-slim \
  python -c "x = bytearray(200 * 1024 * 1024); print('jamais affiché')"
echo "code de sortie : $?"              # 137
docker inspect oom --format '{{.State.OOMKilled}} {{.State.ExitCode}}'
docker rm oom
```

**CPU : throttling, pas de kill :**

```bash
docker run --rm -d --name cpu --cpus 0.25 alpine sh -c 'while :; do :; done'
docker stats --no-stream cpu            # plafonné à ~25 %
docker rm -f cpu
```

**Couches et copy-on-write :**

```bash
docker run --name cow alpine sh -c 'echo modif > /etc/motd; rm /etc/hosts.allow 2>/dev/null; touch /nouveau'
docker diff cow                         # C = changé, A = ajouté, D = supprimé
docker rm cow
```

---

## Lab 1.2 — Autopsie d'un mauvais Dockerfile (≈ 25 min)

```bash
time docker build -f 01-docker/labs/Dockerfile.naive -t taskapi:naive app/
docker images taskapi:naive              # taille ?
docker history taskapi:naive
docker run --rm taskapi:naive env | grep DB_PASSWORD     # 😱
docker run --rm taskapi:naive id                         # root
docker run --rm taskapi:naive ls /app                    # tests, .venv éventuel, etc.
hadolint 01-docker/labs/Dockerfile.naive
```

Modifie un commentaire dans `app/src/taskapi/routes.py` et relance le build : **combien de temps ?** Pourquoi toutes les dépendances sont-elles réinstallées ?

Teste l'arrêt :

```bash
docker run -d --name naive -e DATABASE_URL=sqlite:////tmp/t.db taskapi:naive
sleep 3; time docker stop naive          # ~10 s : pourquoi ?
docker rm naive
```

📝 **Écris dans ton carnet la liste des problèmes** (il y en a au moins 10) avant de passer au lab suivant.

---

## Lab 1.3 — Le Dockerfile de production (≈ 50 min)

Crée `app/Dockerfile` **toi-même**, avec ces exigences :

1. Multi-stage : une étape `builder` qui crée un venv dans `/opt/venv`, une étape `runtime` en `python:3.12-slim`.
2. Ordre des couches optimal pour le cache (dépendances avant le code).
3. Cache pip BuildKit (`RUN --mount=type=cache,...`).
4. Utilisateur non-root avec **UID numérique 10001**.
5. Code non modifiable par l'utilisateur d'exécution.
6. `ARG APP_VERSION` et `GIT_SHA` → labels OCI + variable d'env `APP_VERSION`.
7. `HEALTHCHECK` sans installer curl (indice : Python est déjà là).
8. `ENTRYPOINT` en forme exec : `uvicorn taskapi.main:create_app --factory --host 0.0.0.0 --port 8000 --no-access-log`.

Crée aussi `app/.dockerignore`.

```bash
docker build -t taskapi:dev \
  --build-arg APP_VERSION=$(git rev-parse --short HEAD) \
  --build-arg GIT_SHA=$(git rev-parse HEAD) app/
docker images | grep taskapi             # compare naive vs dev
hadolint app/Dockerfile                  # 0 avertissement visé
```

Vérifications :

```bash
docker run --rm taskapi:dev id                                   # uid=10001
docker run --rm --entrypoint sh taskapi:dev -c 'touch /app/src/x' # Permission denied ✅
docker image inspect taskapi:dev --format '{{json .Config.Labels}}' | jq
```

Teste le cache : modifie un commentaire dans `routes.py`, rebuild → seule la dernière couche est refaite (quelques secondes).

Teste l'arrêt propre :

```bash
docker run -d --name t -e DATABASE_URL=sqlite:////tmp/t.db taskapi:dev
sleep 3; time docker stop t              # < 1 s ✅
docker logs t | tail -2                  # log "arrêt"
docker rm t
```

> Bloqué ? Compare avec [solutions/app/Dockerfile](solutions/app/Dockerfile).

---

## Lab 1.4 — Scanner et inventorier (≈ 20 min)

```bash
trivy image taskapi:naive --severity HIGH,CRITICAL --quiet | tail -20
trivy image taskapi:dev   --severity HIGH,CRITICAL --quiet | tail -20
trivy image taskapi:dev --severity CRITICAL --ignore-unfixed --exit-code 1; echo "exit=$?"
trivy image taskapi:dev --format cyclonedx --output sbom-taskapi.json
jq '.components | length' sbom-taskapi.json          # nombre de composants inventoriés
trivy fs --scanners secret,misconfig app/            # secrets et mauvaises configs dans le code
```

Questions :
- Combien de CVE en moins entre `naive` et `dev` ? D'où viennent celles qui restent (OS ou Python) ?
- Que signifie `--ignore-unfixed` et pourquoi est-ce raisonnable pour un *gate* de CI ?

**Figer les versions (reproductibilité)** :

```bash
docker run --rm --entrypoint pip taskapi:dev freeze > app/requirements.lock
cat app/requirements.lock
```

> En entreprise, on installerait depuis ce fichier figé (ou via `pip-tools` / `uv lock`), et un outil comme Dependabot/Renovate proposerait les montées de version par PR.

---

## Lab 1.5 — Compose : l'application complète (≈ 40 min)

Écris `compose.yaml` **à la racine du repo** :

- service `db` : `postgres:17-alpine`, mot de passe via **secret Compose** (`POSTGRES_PASSWORD_FILE`), volume nommé, healthcheck `pg_isready` ;
- service `api` : build de `./app`, attend que la base soit *healthy*, port publié **uniquement sur 127.0.0.1**, durcissement (`read_only`, `tmpfs`, `cap_drop`, `no-new-privileges`), limites CPU/RAM ;
- deux réseaux : `backend` (internal) et `frontend`.

```bash
mkdir -p secrets && openssl rand -hex 16 | tr -d '\n' > secrets/db_password.txt
docker compose config                    # valide et affiche le YAML résolu
docker compose up -d --build
docker compose ps                        # STATUS healthy
docker compose logs -f api               # Ctrl+C pour sortir
curl -s localhost:8000/readyz
curl -s -X POST localhost:8000/api/tasks -H 'content-type: application/json' -d '{"title":"persistée ?"}'
```

**Persistance :**

```bash
docker compose down                      # supprime conteneurs + réseaux, PAS le volume
docker compose up -d
curl -s localhost:8000/api/tasks | jq    # la tâche est toujours là
```

**Isolation réseau :**

```bash
docker compose exec db sh -c 'wget -qO- -T 3 https://github.com || echo "pas d accès sortant ✅"'
docker compose exec api python -c "import socket; print(socket.gethostbyname('db'))"   # DNS interne
```

**Résilience :**

```bash
docker compose stop db
curl -s -w ' %{http_code}\n' localhost:8000/readyz      # 503 : pas prêt
curl -s -w ' %{http_code}\n' localhost:8000/healthz     # 200 : vivant
docker compose start db; sleep 5
curl -s -w ' %{http_code}\n' localhost:8000/readyz      # 200
```

C'est exactement la distinction liveness/readiness que Kubernetes exploitera demain.

**Debug réseau dans le namespace d'un conteneur :**

```bash
docker run --rm -it --network container:$(docker compose ps -q api) nicolaka/netshoot \
  bash -c 'ss -tlnp; nc -zv db 5432'
```

---

## Lab 1.6 — Pousser l'image sur GHCR (≈ 15 min)

1. Sur GitHub : **Settings → Developer settings → Personal access tokens → Tokens (classic)** → *Generate new token (classic)*, scopes `write:packages` + `read:packages`, expiration 30 jours. (GHCR n'accepte pas encore les tokens *fine-grained*.)
2. Dans WSL (le token n'apparaît ni dans l'historique ni dans un fichier commité) :

```bash
read -rs CR_PAT        # colle le token, Entrée
echo "$CR_PAT" | docker login ghcr.io -u tadeyayaoye --password-stdin
unset CR_PAT
TAG=$(git rev-parse --short HEAD)
docker tag taskapi:dev ghcr.io/tadeyayaoye/taskapi:$TAG
docker push ghcr.io/tadeyayaoye/taskapi:$TAG
```

3. Sur GitHub → ton profil → **Packages** → `taskapi` → *Package settings* → **Change visibility → Public** (indispensable pour que kind puisse la tirer sans identifiants).

Remarque : grâce au label `org.opencontainers.image.source`, le package est automatiquement relié au repo.

⚠ Regarde `~/.docker/config.json` : le jeton y est stocké encodé en base64, **pas chiffré**. En entreprise on configure un *credential helper*.

---

## 🏁 Challenge (sans guide)

Obtiens une image `taskapi:hardened` qui :
- fait **moins de 200 Mo** ;
- démarre avec `docker run --read-only --cap-drop ALL --security-opt no-new-privileges --user 10001` ;
- n'a **aucune CVE CRITICAL corrigeable** (`trivy image --severity CRITICAL --ignore-unfixed --exit-code 1`) ;
- passe `hadolint` sans avertissement ;
- bonus : construis-la en multi-arch (`docker buildx build --platform linux/amd64,linux/arm64`) avec un builder `docker-container` ; bonus 2 : essaie une base distroless (`gcr.io/distroless/python3-debian12`) et note les difficultés (venv, version Python, healthcheck sans shell…).

---

## ✅ Validation

```bash
make check-01
```
