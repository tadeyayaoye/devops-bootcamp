# Module 01 — Docker et la conteneurisation en profondeur

> **Objectif** : comprendre ce qu'est *vraiment* un conteneur (côté noyau), écrire un Dockerfile de niveau production, orchestrer localement avec Compose, et sécuriser/scanner ses images.
>
> **Durée** : cours ~1 h 45 · labs ~3 h · quiz 30 min

---

## 1. Un conteneur n'est pas une VM

```
        Machines virtuelles                         Conteneurs
┌──────┐ ┌──────┐ ┌──────┐               ┌──────┐ ┌──────┐ ┌──────┐
│ App  │ │ App  │ │ App  │               │ App  │ │ App  │ │ App  │
│ Libs │ │ Libs │ │ Libs │               │ Libs │ │ Libs │ │ Libs │
│Noyau │ │Noyau │ │Noyau │               └──┬───┘ └──┬───┘ └──┬───┘
│invité│ │invité│ │invité│                  └── processus isolés ──┘
└──┬───┘ └──┬───┘ └──┬───┘               ┌──────────────────────────┐
┌──┴────────┴────────┴───┐               │   UN SEUL noyau (hôte)   │
│      Hyperviseur       │               └──────────────────────────┘
└────────────────────────┘
```

Un conteneur est **un processus Linux ordinaire** auquel le noyau applique trois mécanismes :

### 1.1 Namespaces : ce que le processus *voit*

| Namespace | Isole | Conséquence |
|---|---|---|
| `pid` | l'arbre des processus | ton appli se voit en PID 1 |
| `net` | interfaces, IP, ports, routes | chaque conteneur a son `eth0` et son `localhost` |
| `mnt` | les points de montage | le conteneur voit son propre `/` |
| `uts` | hostname | `hostname` = ID du conteneur |
| `ipc` | mémoire partagée, sémaphores | |
| `user` | correspondance des UID (rootless) | root dans le conteneur ≠ root sur l'hôte (si activé) |
| `cgroup` | la vue de la hiérarchie cgroup | |

### 1.2 cgroups (v2) : ce que le processus peut *consommer*

CPU (`cpu.max` → quota/période), mémoire (`memory.max` → au-delà : **OOM kill**), I/O, nombre de PIDs. C'est ce que règlent `docker run --memory 256m --cpus 0.5` et, plus tard, les `resources.limits` Kubernetes.

> ⚠ Dépasser la limite **mémoire** = processus tué (exit code **137** = 128 + 9, SIGKILL). Dépasser la limite **CPU** = processus *ralenti* (throttling), pas tué.

### 1.3 Système de fichiers en couches (OverlayFS)

```
  ┌───────────────────────────┐  ← couche du conteneur (lecture/écriture, éphémère)
  ├───────────────────────────┤
  │ COPY src/        (couche 4)│
  │ RUN pip install  (couche 3)│  ← couches de l'image (lecture seule,
  │ COPY requirements(couche 2)│     partagées entre tous les conteneurs
  │ FROM python:slim (couche 1)│     et toutes les images qui les utilisent)
  └───────────────────────────┘
```

- Modifier un fichier d'une couche basse = **copy-on-write** dans la couche du conteneur.
- Supprimer un fichier dans une couche ultérieure ne le retire **pas** de l'image (il reste dans la couche précédente) → un secret copié puis supprimé **reste extractible**.
- À la suppression du conteneur, sa couche disparaît : d'où les **volumes** pour les données.

### 1.4 La pile d'exécution

```
docker CLI ──REST /var/run/docker.sock──► dockerd ──gRPC──► containerd ──► containerd-shim ──► runc ──► processus
                                          (API, build,       (images,          (garde le          (crée namespaces
                                           réseaux, volumes)  cycle de vie)      conteneur vivant)   + cgroups puis exec)
```

- **OCI** (Open Container Initiative) standardise le format d'**image** (*image-spec*), le **runtime** (*runtime-spec*, implémenté par runc, crun, gVisor, Kata…) et la **distribution** (registres).
- **Kubernetes n'utilise plus dockerd** depuis la v1.24 : le kubelet parle directement à **containerd** (ou CRI-O) via l'interface CRI. Les images construites par Docker restent 100 % compatibles (c'est de l'OCI).

---

## 2. Images

### 2.1 Anatomie

Une image = un **manifeste** (liste de couches + config) adressé par un **digest** `sha256:…`. Un **tag** (`3.12-slim`) est une étiquette **mobile** qui pointe vers un digest à un instant T.

```
ghcr.io/tadeyayaoye/taskapi:1a2b3c4@sha256:9f86d0…
└─registre─┘└──dépôt──────┘└─tag─┘ └──digest (immuable)─┘
```

- Image **multi-architecture** : un *index* (manifest list) qui pointe vers un manifeste par plateforme (`linux/amd64`, `linux/arm64`).
- Inspecter : `docker image inspect`, `docker history --no-trunc`, `docker buildx imagetools inspect`.

### 2.2 Stratégie de tags

| Tag | Usage |
|---|---|
| `latest` | ❌ jamais en prod (on ne sait pas ce qui tourne, pas de rollback fiable) |
| `1.4.2` (SemVer) | releases |
| `sha-1a2b3c4` (commit Git) | ✅ CI : traçabilité parfaite image ↔ code |
| `main`, `pr-42` | tags mobiles pratiques pour les environnements éphémères |
| `@sha256:…` | ✅ le plus sûr : immuable (on épingle les images de base par digest dans les équipes matures) |

Principe **« build once, deploy many »** : on construit l'image **une seule fois** en CI, puis on promeut *la même* image (même digest) de dev à prod. On ne rebuild jamais pour la prod.

### 2.3 Registres

Docker Hub (limites de pull pour les anonymes et comptes gratuits), **GHCR** (GitHub), GitLab Registry, Harbor (on-prem, scan intégré), ECR/ACR/Artifact Registry (cloud). Authentification : `docker login <registre>` → le jeton est stocké dans `~/.docker/config.json` (en clair sans *credential helper* !).

---

## 3. Le Dockerfile, instruction par instruction

| Instruction | Ce qu'il faut savoir |
|---|---|
| `FROM image:tag AS nom` | base ; plusieurs `FROM` = **multi-stage** |
| `ARG` | variable de **build** uniquement (visible dans `docker history` → jamais de secret) ; un `ARG` déclaré avant `FROM` doit être redéclaré après pour être utilisé |
| `ENV` | variable présente **au runtime** (et dans les étapes suivantes) |
| `WORKDIR` | crée et se place dans le dossier (évite les `cd`) |
| `COPY` vs `ADD` | toujours `COPY` ; `ADD` décompresse les archives et télécharge des URLs (comportements implicites = surprises) |
| `RUN` | chaque `RUN` = une couche ; enchaîner `apt-get update && apt-get install … && rm -rf /var/lib/apt/lists/*` dans le **même** RUN |
| `USER` | change l'utilisateur pour les instructions suivantes et le runtime ; préférer un **UID numérique** (Kubernetes peut alors vérifier `runAsNonRoot`) |
| `EXPOSE` | **documentation** uniquement, n'ouvre rien |
| `HEALTHCHECK` | utilisé par Docker/Compose ; **ignoré par Kubernetes** (qui a ses propres probes) |
| `ENTRYPOINT` / `CMD` | voir ci-dessous |
| `LABEL` | métadonnées (standard `org.opencontainers.image.*`) ; `…image.source` relie l'image GHCR au repo |

### 3.1 ENTRYPOINT, CMD, forme *exec* et PID 1

```dockerfile
CMD uvicorn app:app            # forme SHELL → /bin/sh -c "uvicorn …" : sh est PID 1
CMD ["uvicorn", "app:app"]     # forme EXEC  → uvicorn est PID 1 ✅
```

Avec la forme shell, `sh` reçoit SIGTERM et **ne le transmet pas** à ton appli → `docker stop` attend 10 s puis SIGKILL. Résultat : arrêts lents et requêtes coupées à chaque déploiement.

- `ENTRYPOINT` = l'exécutable ; `CMD` = les arguments par défaut (remplaçables par `docker run image <args>`).
- Le PID 1 a aussi pour rôle de **récolter les zombies**. Si ton appli lance des sous-processus, utilise `docker run --init` (tini) ou ajoute `tini` dans l'image.

### 3.2 Le cache de build : l'ordre compte

Docker réutilise une couche si l'instruction **et** ses entrées (fichiers copiés) n'ont pas changé ; dès qu'une couche est invalidée, **toutes les suivantes** sont reconstruites.

```dockerfile
# ❌ chaque modification du code réinstalle toutes les dépendances
COPY . .
RUN pip install -r requirements.txt

# ✅ les dépendances ne sont réinstallées que si requirements.txt change
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY src/ ./src/
```

Règle : **du moins changeant au plus changeant**.

### 3.3 Multi-stage build

```dockerfile
FROM python:3.12-slim AS builder      # outils de build, compilateurs, cache pip…
RUN python -m venv /opt/venv && /opt/venv/bin/pip install -r requirements.txt

FROM python:3.12-slim AS runtime      # uniquement ce qui sert à l'exécution
COPY --from=builder /opt/venv /opt/venv
```

Gains : image plus petite, **surface d'attaque** réduite (pas de gcc, pas de pip cache, pas de dépendances de dev), séparation build/runtime. En Go/Rust on va jusqu'à `FROM scratch` ou distroless.

### 3.4 Choisir son image de base

| Base | Taille | Remarques |
|---|---|---|
| `python:3.12` (Debian complète) | ~1 Go | pratique pour builder, jamais pour le runtime |
| `python:3.12-slim` | ~130 Mo | ✅ bon compromis, glibc |
| `python:3.12-alpine` | ~50 Mo | musl libc : beaucoup de wheels Python inutilisables → compilation, builds lents, bugs subtils (DNS, perfs). À éviter en Python |
| distroless / Chainguard / Docker Hardened Images | ~50 Mo | pas de shell ni de gestionnaire de paquets : très peu de CVE, debug plus dur (`kubectl debug`) |

### 3.5 BuildKit

Moteur de build par défaut. Fonctions utiles :

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt   # cache persistant entre builds
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci                       # secret de build JAMAIS stocké dans une couche
```

`docker buildx build --platform linux/amd64,linux/arm64 --push …` pour le multi-arch ; `--cache-from/--cache-to type=registry` pour partager le cache entre runners CI.

### 3.6 `.dockerignore`

Le *contexte de build* (le dossier envoyé au démon) doit être minimal : `.git`, `.venv`, `.env`, tests, artefacts. Sans `.dockerignore`, un `COPY . .` embarque ton `.env` dans l'image.

---

## 4. Réseau

| Driver | Comportement |
|---|---|
| `bridge` (défaut) | réseau privé NATé ; `-p 8080:8000` publie un port de l'hôte |
| **réseau bridge défini par l'utilisateur** | ✅ ajoute un **DNS interne** : les conteneurs se joignent par leur **nom** (`db:5432`). C'est ce que crée Compose. |
| `host` | partage la pile réseau de l'hôte (pas d'isolation, pas de `-p`) |
| `none` | aucune interface |

- `-p 8000:8000` écoute sur **toutes les interfaces** de l'hôte ; `-p 127.0.0.1:8000:8000` seulement en local.
- ⚠ Les ports publiés par Docker contournent souvent le pare-feu `ufw` (règles iptables propres à Docker).
- `internal: true` (Compose) : réseau sans accès sortant/entrant → idéal pour une base de données.

---

## 5. Stockage

| Type | Géré par | Usage |
|---|---|---|
| **Volume nommé** | Docker (`/var/lib/docker/volumes`) | ✅ données persistantes (Postgres) |
| **Bind mount** | toi (chemin de l'hôte) | code en développement (hot reload), fichiers de config |
| **tmpfs** | RAM | fichiers temporaires avec `--read-only` |

`docker volume ls / inspect / prune`. Sauvegarde d'un volume : `docker run --rm -v pgdata:/data -v $PWD:/backup alpine tar czf /backup/pg.tgz -C /data .`

---

## 6. Docker Compose

Décrit une application multi-conteneurs en YAML (spécification *Compose Specification*, fichier `compose.yaml`).

```yaml
services:
  api:
    build: ./app
    depends_on:
      db:
        condition: service_healthy   # attend le healthcheck, pas juste le démarrage
    environment: { DB_HOST: db }
  db:
    image: postgres:17-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U taskapi"]
    volumes: [pgdata:/var/lib/postgresql/data]
volumes:
  pgdata:
```

Concepts : `depends_on` + `condition`, `healthcheck`, `env_file`, **`secrets`** (montés en fichiers dans `/run/secrets/`), `profiles` (services optionnels), `deploy.resources.limits`, réseaux multiples, `restart: unless-stopped`.

Commandes : `docker compose up -d --build`, `ps`, `logs -f api`, `exec api sh`, `down` (garde les volumes) / `down -v` (⚠ supprime les volumes), `config` (affiche le YAML résolu), `watch` (resynchronise le code en dev).

> Compose est parfait pour le **développement local** et les petits déploiements mono-machine. Dès qu'on veut de la haute disponibilité, du rolling update, de l'autoscaling multi-nœuds → Kubernetes.

---

## 7. Sécurité des conteneurs

### 7.1 Au build

- Image de base minimale et **à jour** (rebuild régulier pour récupérer les patchs).
- **Utilisateur non-root** (`USER 10001`) : si l'appli est compromise, l'attaquant n'est pas root dans le conteneur.
- Pas de secrets dans l'image (ni `ENV`, ni `ARG`, ni `COPY` d'un `.env`).
- Code applicatif possédé par root et non modifiable par l'utilisateur d'exécution.
- Linter : **hadolint** (bonnes pratiques Dockerfile + shellcheck sur les `RUN`).

### 7.2 Au runtime

```bash
docker run --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  --memory 256m --cpus 0.5 --pids-limit 200 \
  --user 10001:10001 image
```

- **Capabilities** : root est découpé en ~40 privilèges (`NET_BIND_SERVICE`, `SYS_ADMIN`…). On retire tout et on rajoute le strict nécessaire.
- `--privileged` = quasiment root sur l'hôte : à bannir.
- Jamais monter `/var/run/docker.sock` dans un conteneur non maîtrisé.

### 7.3 Supply chain

| Outil | Rôle |
|---|---|
| **Trivy**, Grype | scan de CVE (OS + dépendances applicatives), IaC, secrets |
| **SBOM** (SPDX, CycloneDX) | inventaire des composants de l'image (`trivy image --format cyclonedx`, `docker buildx build --sbom=true`) |
| **cosign** (Sigstore) | signature d'images + attestations (provenance SLSA) |
| Docker Scout | équivalent intégré à Docker |

Lire un rapport de CVE : **sévérité** (CVSS), **corrigeable ou non** (`--ignore-unfixed`), **atteignable ou non** (une CVE dans une lib jamais appelée…). On bloque en CI sur `CRITICAL` corrigeables, on suit le reste.

---

## 8. Debug : la boîte à outils

```bash
docker ps -a                          # y compris les conteneurs arrêtés
docker logs -f --tail 50 <c>          # stdout/stderr
docker inspect <c> | jq '.[0].State'  # code de sortie, OOMKilled, healthcheck
docker exec -it <c> sh                # entrer (si l'image a un shell)
docker stats                          # CPU/RAM en direct
docker events                         # flux d'événements du démon
docker system df                      # espace disque ; docker system prune pour nettoyer
docker run --rm -it --network container:<c> nicolaka/netshoot   # outils réseau DANS le namespace réseau du conteneur
```

Codes de sortie à connaître : **0** OK · **1** erreur applicative · **125** erreur Docker · **126** commande non exécutable · **127** commande introuvable · **137** SIGKILL (souvent OOM) · **143** SIGTERM.

---

## 9. Pièges classiques

- Image de 1 Go parce que `FROM python:3.12` + dépendances de dev + caches.
- `apt-get update` dans un `RUN` séparé de `apt-get install` → cache périmé, paquets introuvables.
- `latest` partout → impossible de savoir ce qui tourne.
- Conteneur qui met 10 s à s'arrêter → forme shell ou appli qui ignore SIGTERM.
- Données Postgres perdues → pas de volume, ou `docker compose down -v`.
- `localhost` dans un conteneur = le conteneur lui-même, pas ta machine ni la base.
- PostgreSQL 18 : l'image officielle a changé son chemin de données (`/var/lib/postgresql/18/docker`) → on reste en 17 ici, mais lis toujours les notes de version d'une image avant de monter de version majeure.

---

## Pour aller plus loin

- [Docker docs — Build best practices](https://docs.docker.com/build/building/best-practices/)
- [Containers from scratch (Liz Rice, vidéo)](https://www.youtube.com/watch?v=8fi7uSYlOdc) — un conteneur en 60 lignes de Go
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
