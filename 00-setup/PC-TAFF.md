# Module 00 — Variante « PC du taff »

Le bootcamp est calibré pour le PC perso (16 Go, réseau libre). Le PC du taff est différent :

| | PC perso | PC du taff |
|---|---|---|
| RAM physique | 16 Go | 8 Go (~7,3 utilisables) |
| RAM donnée à WSL | 12 Go | **5 Go** |
| Réseau | direct | pare-feu **Palo Alto** d'Aubay qui inspecte le HTTPS |
| Docker | Docker Engine dans Ubuntu | idem — Docker Desktop est installé côté Windows mais **on ne s'en sert pas** |
| Droits admin Windows | oui | non (PC géré par Intune) |

---

## Pourquoi `bootstrap-wsl.sh` plantait

**1. Il croyait que Docker était déjà installé.**
Docker Desktop (côté Windows) dépose un faux `docker` dans `C:\Program Files\Docker\...`, et WSL ajoute le PATH Windows au PATH Linux. `command -v docker` répondait donc « trouvé », le script sautait l'installation de Docker Engine, puis `sudo usermod -aG docker` échouait (`group 'docker' does not exist`) et `set -e` arrêtait tout.
→ Corrigé : `have()` ignore désormais les exécutables situés sous `/mnt/`.

**2. Le pare-feu d'Aubay ré-signe certaines connexions HTTPS.**
Pour `apt.releases.hashicorp.com`, `cli.github.com`, `raw.githubusercontent.com`, `release-assets.githubusercontent.com`, `registry.k8s.io`… le certificat présenté n'est pas celui du site mais un certificat `PaloAlto_13LP` signé par l'autorité `paloalto.aubay.com`. Windows fait confiance à cette autorité (Intune l'a installée), Ubuntu non → `SSL certificate problem: self-signed certificate in certificate chain`.
→ Corrigé : le bootstrap peut copier l'autorité depuis le magasin de certificats Windows vers Ubuntu (`CORP_CA_PATTERN`).

Pour le vérifier toi-même :

```bash
echo | openssl s_client -connect apt.releases.hashicorp.com:443 2>/dev/null | grep 'i:'
```

---

## Mise en place (≈ 20 min)

### 1. Limiter WSL à 5 Go

Dans PowerShell (pas besoin d'être admin) :

```powershell
notepad $env:USERPROFILE\.wslconfig     # colle le contenu de wslconfig.taff.example
wsl --shutdown
```

### 2. Mettre Docker Desktop de côté

Quitte Docker Desktop (icône de la barre des tâches → *Quit*) et décoche *Start Docker Desktop when you sign in* dans ses réglages. Il consomme ~1-2 Go de RAM de plus et, dans une entreprise de la taille d'Aubay, son utilisation demande une licence payante. Le Docker Engine installé dans Ubuntu suffit.

### 3. Lancer le bootstrap avec l'autorité du proxy

```bash
cd ~/devops-bootcamp
CORP_CA_PATTERN=paloalto.aubay.com ./scripts/bootstrap-wsl.sh
```

Le certificat est rangé dans `~/.bootcamp/ca/` : les relances suivantes le réinstallent même sans la variable.

### 4. Le profil « taff » dans `~/.bashrc`

Ajoute à la fin de `~/.bashrc` **sur le PC du taff uniquement** :

```bash
# >>> pc-taff >>>
export KIND_CONFIG=02-kubernetes-bases/kind/kind-config.taff.yaml   # cluster kind à 1 nœud + certificats
export MIN_WSL_RAM_GB=4                                             # seuil de make check-00
# outils qui n'utilisent pas le magasin de certificats du système
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt        # python requests (ansible-galaxy…)
export PIP_CERT=/etc/ssl/certs/ca-certificates.crt                  # pip / pipx
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt       # node / npm
# <<< pc-taff <<<
```

Puis `source ~/.bashrc`, `newgrp docker` (ou rouvre le terminal) et :

```bash
make tools
make check-00
```

---

## Budget mémoire avec 5 Go

Un seul gros bloc à la fois, et `make status` / `docker stats` pour surveiller.

| Bloc | RAM approx. | Sur le PC du taff ? |
|---|---|---|
| Cluster kind **1 nœud** + Traefik | ~1,5 Go | ✅ modules 02 → 11 |
| + Argo CD | ~0,5 Go | ✅ |
| + Prometheus / Grafana / Alertmanager | ~1,5 Go | ⚠ juste : arrête la CI avant |
| + Loki / Tempo / Alloy | ~1 Go | ⚠ avec le swap, ça rame : préfère le PC perso pour le module 10 |
| Jenkins | ~1,5 Go | ✅ avec le cluster arrêté (`make cluster-down`) |
| SonarQube + Postgres | ~3 Go | ⚠ seul, tout le reste arrêté |
| Airflow (7 conteneurs) | ~4 Go | ❌ PC perso |
| Zabbix + labo Ansible | ~2 Go | ✅ seul |
| XL Release | ~3-4 Go | ❌ PC perso |

Au **module 04** (Terraform), mets `worker_count = 0` et ajoute au nœud control-plane le même montage `/etc/ssl/certs/ca-certificates.crt` que dans `kind-config.taff.yaml` (c'est un bon exercice sur les blocs `dynamic`).

## Encore bloqué ?

- **Image Docker qui télécharge depuis un site intercepté** pendant le `docker build` (ex. `curl https://raw.githubusercontent.com/...` dans un `Dockerfile`) : le conteneur ne connaît pas l'autorité. Copie `~/.bootcamp/ca/*.crt` dans l'image (`/usr/local/share/ca-certificates/` puis `update-ca-certificates`), uniquement sur ce PC.
- **Site entièrement bloqué** (pas seulement inspecté, `curl` renvoie une page du pare-feu ou un timeout) : demande au support Aubay de l'autoriser, ou fais ce module sur le PC perso.
