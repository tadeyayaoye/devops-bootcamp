# Module 00 — Poste de travail, Linux et Git en profondeur

> **Objectif du jour** : un poste DevOps propre (WSL2 + Docker Engine + outils), les réflexes Linux indispensables, et une maîtrise de Git qui va au-delà de `add / commit / push`.
>
> **Durée** : cours ~1 h 30 · labs ~3 h · quiz 30 min

---

## 1. WSL2 : un vrai Linux dans Windows

### 1.1 Ce que c'est vraiment

WSL2 n'est **pas** une émulation : c'est une **VM légère Hyper-V** qui fait tourner un **vrai noyau Linux** (maintenu par Microsoft). Toutes tes distributions (Ubuntu…) partagent cette VM et ce noyau.

```
┌──────────────────────── Windows 11 ────────────────────────┐
│  Navigateur → http://localhost:8080  ──(localhost forwarding)──┐
│                                                               │
│  ┌──────────── VM utilitaire WSL2 (Hyper-V) ───────────────┐  │
│  │  Noyau Linux 6.x                                        │◄─┘
│  │  ┌──────── Ubuntu 24.04 ────────┐                        │
│  │  │ systemd → dockerd → containerd → runc → conteneurs   │
│  │  │ ~/devops-bootcamp (ext4, rapide)                     │
│  │  │ /mnt/c → disque Windows (9P, LENT)                   │
│  │  └──────────────────────────────┘                        │
│  └──────────────────────────────────────────────────────────┘
└───────────────────────────────────────────────────────────────┘
```

**Conséquences pratiques :**

| Sujet | À retenir |
|---|---|
| Système de fichiers | Travaille **dans `~`** (disque virtuel ext4). `/mnt/c` passe par un protocole réseau (9P) : 5 à 20× plus lent, et les permissions Unix y sont émulées (scripts non exécutables, `chmod` sans effet…). |
| Réseau | Mode NAT par défaut : un port ouvert dans WSL (ex. 8080) est **automatiquement relayé** sur `localhost` côté Windows. Les IP des conteneurs Docker, elles, ne sont pas joignables depuis Windows. |
| Ressources | La VM prend par défaut jusqu'à 50 % de la RAM. On la plafonne avec `%UserProfile%\.wslconfig`. |
| systemd | Activé via `/etc/wsl.conf` (`[boot] systemd=true`), c'est le cas par défaut sur Ubuntu récent. Indispensable pour gérer `docker` comme un service. |
| Arrêt | `wsl --shutdown` (PowerShell) arrête la VM : nécessaire après une modification de `.wslconfig`. |

### 1.2 Docker Engine vs Docker Desktop

- **Docker Desktop** : application Windows qui embarque sa propre distribution WSL, une GUI, Kubernetes intégré… Gratuit pour usage personnel, payant pour les grandes entreprises (> 250 salariés **ou** > 10 M$ de CA).
- **Docker Engine** (notre choix) : on installe `dockerd` directement dans Ubuntu, comme sur un serveur Linux. Avantages : 100 % gratuit sans condition, comportement identique à un serveur de prod/CI, compréhension de ce qui tourne réellement.

Alternatives à connaître : **Podman** (sans démon, rootless par défaut, CLI compatible), **Rancher Desktop**, **colima** (macOS).

---

## 2. Linux : les réflexes DevOps

Tu n'as pas besoin d'être administrateur système, mais ces notions reviennent **tous les jours** (et en entretien).

### 2.1 Processus et signaux — fondamental pour les conteneurs

| Signal | Numéro | Sens | Interceptable ? |
|---|---|---|---|
| `SIGTERM` | 15 | « Arrête-toi proprement » | Oui → l'appli ferme ses connexions, finit ses requêtes |
| `SIGKILL` | 9 | Mort immédiate, par le noyau | **Non** |
| `SIGINT` | 2 | Ctrl+C | Oui |
| `SIGHUP` | 1 | Historiquement « terminal fermé », souvent « recharge ta config » (nginx, sshd) | Oui |

👉 `docker stop` et la suppression d'un pod Kubernetes envoient **SIGTERM**, attendent un délai de grâce (10 s pour Docker, `terminationGracePeriodSeconds: 30` pour K8s), puis **SIGKILL**. Si ton appli n'est pas PID 1 ou ignore SIGTERM, elle se fait tuer brutalement → requêtes coupées. On y revient au module 01.

```bash
ps aux --sort=-%mem | head        # qui consomme ?
pgrep -a uvicorn                  # trouver un process
kill -TERM <pid>  /  kill -9 <pid>
top / htop                        # vue temps réel
```

### 2.2 Utilisateurs, groupes, permissions

```
-rwxr-x---  1 alice devops  4096  deploy.sh
 │└┬┘└┬┘└┬┘   proprio groupe
 │ u  g  o    → u=rwx (7), g=r-x (5), o=--- (0)  → chmod 750
 └ type (- fichier, d dossier, l lien)
```

- `sudo usermod -aG docker $USER` : t'ajoute au groupe `docker` → accès au socket `/var/run/docker.sock`. ⚠ **Être dans le groupe docker équivaut à être root** sur la machine (on peut monter `/` dans un conteneur). À savoir dire en entretien.
- Un nouveau groupe n'est pris en compte **qu'à la prochaine connexion** (d'où « ferme et rouvre ton terminal »).
- UID/GID : les conteneurs manipulent des **numéros**, pas des noms. Un fichier créé par l'UID 1000 dans un conteneur appartient à l'UID 1000 sur l'hôte.

### 2.3 systemd et journaux

```bash
systemctl status docker           # état d'un service
sudo systemctl restart docker
sudo systemctl enable --now docker   # démarrage auto + maintenant
journalctl -u docker -f           # logs du service en continu
journalctl -u docker --since "10 min ago"
```

### 2.4 Réseau : le kit de diagnostic

| Question | Commande |
|---|---|
| Quels ports écoutent ? | `ss -tlnp` |
| Le service HTTP répond-il ? | `curl -sv http://localhost:8000/healthz` |
| Quel code HTTP / quel temps ? | `curl -o /dev/null -s -w '%{http_code} %{time_total}s\n' URL` |
| Le DNS résout-il ? | `dig +short github.com` · `getent hosts db` |
| Le port est-il joignable ? | `nc -zv host 5432` |
| Mes interfaces / routes ? | `ip -br a` · `ip route` |

### 2.5 Bash robuste (les scripts de CI en sont pleins)

```bash
#!/usr/bin/env bash
set -euo pipefail   # -e : stop à la 1re erreur ; -u : variable non définie = erreur ;
                    # -o pipefail : une erreur au milieu d'un pipe n'est pas masquée
IFS=$'\n\t'
trap 'echo "échec ligne $LINENO" >&2' ERR
trap 'rm -rf "$TMP"' EXIT           # nettoyage garanti, même en cas d'erreur

NAME="${1:?usage: $0 <name>}"       # argument obligatoire
ENV="${ENV:-dev}"                   # valeur par défaut
```

Autres réflexes : toujours **quoter** les variables (`"$var"`), `$(cmd)` plutôt que les backticks, `[[ ]]` plutôt que `[ ]`, `shellcheck` pour linter.

Redirections : `>` (écrase), `>>` (ajoute), `2>&1` (stderr vers stdout), `&>/dev/null` (tout jeter), `| tee fichier` (afficher et écrire).

### 2.6 Variables d'environnement

Une variable n'est transmise aux processus enfants que si elle est **exportée** (`export FOO=bar`). C'est la base du modèle **12-factor** : la configuration d'une appli vient de l'environnement, ce qui permet la même image en dev et en prod. `env`, `printenv FOO`, `FOO=bar cmd` (pour une seule commande).

---

## 3. Git en profondeur

### 3.1 Le modèle interne (ce qui rend tout le reste logique)

Git est une **base de données d'objets adressés par leur hash** (SHA-1, SHA-256 en option) :

```
commit a1b2c3 ──► tree (racine)  ──► blob (contenu de app.py)
  │ parent         └─► tree (src/) ──► blob …
  ▼
commit 9f8e7d ──► …
```

| Objet | Contient |
|---|---|
| **blob** | le contenu brut d'un fichier (pas son nom) |
| **tree** | une liste (nom, droits, hash) → un dossier |
| **commit** | un tree racine + parent(s) + auteur + message |
| **tag annoté** | un pointeur signé/daté vers un commit |

Une **branche** n'est qu'un fichier contenant un hash de commit (`.git/refs/heads/main`). `HEAD` pointe sur la branche courante. Créer une branche ne coûte rien : on écrit 41 octets.

```bash
git cat-file -p HEAD           # voir le commit courant
git cat-file -p HEAD^{tree}    # voir son arbre
cat .git/HEAD
```

### 3.2 Les trois zones

```
 Working directory ──git add──► Index (staging) ──git commit──► Dépôt (.git)
        ▲                                                         │
        └──────────────── git restore / checkout ◄────────────────┘
```

- `git diff` : working ↔ index · `git diff --staged` : index ↔ dernier commit
- `git add -p` : ajouter **par morceaux** (pour des commits atomiques)
- `git restore fichier` (annule les modifs locales) · `git restore --staged fichier` (désindexe)

### 3.3 Merge vs rebase

```
Avant :        A---B---C  main
                    \
                     D---E  feature

merge :        A---B---C-------M  main          (historique fidèle, commit de merge)
                    \         /
                     D-------E

rebase :       A---B---C---D'---E'  feature     (historique linéaire, NOUVEAUX commits)
```

- **Fast-forward** : si `main` n'a pas bougé, le merge déplace juste le pointeur.
- **Rebase réécrit l'historique** (nouveaux hash). Règle d'or : **ne jamais rebaser une branche déjà partagée** avec d'autres (sauf accord + `push --force-with-lease`).
- `--force-with-lease` plutôt que `--force` : refuse d'écraser si quelqu'un a poussé entre-temps.
- En PR GitHub : *merge commit*, *squash* (1 seul commit sur main, historique propre) ou *rebase and merge*.

### 3.4 Réécrire et réparer

| Besoin | Commande |
|---|---|
| Corriger le dernier commit (non poussé) | `git commit --amend` |
| Nettoyer ses commits avant PR | `git rebase -i main` (squash, fixup, reword, drop) |
| Annuler un commit **déjà poussé** | `git revert <sha>` (crée un commit inverse : sûr) |
| Revenir en arrière localement | `git reset --soft HEAD~1` (garde index + fichiers) · `--mixed` (garde fichiers) · `--hard` (⚠ perd tout) |
| Appliquer un commit d'une autre branche | `git cherry-pick <sha>` |
| Mettre de côté un travail en cours | `git stash push -m "wip"` · `git stash pop` |
| **J'ai tout cassé** | `git reflog` → retrouve le hash d'avant → `git reset --hard <sha>` |
| Trouver le commit qui a introduit un bug | `git bisect start / bad / good` |

> 💡 Le **reflog** enregistre chaque déplacement de `HEAD` pendant ~90 jours. Un commit « perdu » après un `reset --hard` ou un rebase raté est presque toujours récupérable.

### 3.5 Workflows d'équipe

| Workflow | Principe | Quand |
|---|---|---|
| **GitHub Flow** | `main` toujours déployable, branches courtes, PR, merge, déploiement | La majorité des équipes web/cloud |
| **Trunk-based** | Tout le monde intègre sur `main` au moins 1×/jour, *feature flags* pour masquer le travail en cours | Équipes très matures en CI/CD (recommandé par DORA) |
| **GitFlow** | `develop`, `release/*`, `hotfix/*`… | Logiciels livrés par versions (moins adapté au déploiement continu) |

### 3.6 Conventions qui font pro

**Conventional Commits** — lisibles par les humains *et* les outils (génération de changelog, versionnage sémantique automatique) :

```
feat(api): ajoute le filtre ?done= sur /api/tasks
fix(db): échappe le mot de passe dans l'URL de connexion
chore(deps): bump fastapi
ci: ajoute le scan Trivy
docs: README du module 03
refactor!: renomme /health en /healthz    ← le "!" signale un breaking change
```

**SemVer** `MAJEUR.MINEUR.CORRECTIF` : majeur = rupture de compatibilité, mineur = fonctionnalité compatible, correctif = bug. Tags annotés : `git tag -a v1.2.0 -m "..."` puis `git push --tags`.

### 3.7 GitHub côté plateforme

| Fonction | À quoi ça sert |
|---|---|
| **Pull Request** | revue de code, discussion, déclencheur de CI |
| **Branch protection / Rulesets** | interdire le push direct et le force-push sur `main`, exiger des checks verts et des approbations |
| **CODEOWNERS** | demande automatiquement la revue des propriétaires d'un dossier |
| **Actions** | CI/CD intégrée (module 07) |
| **Packages / GHCR** | registre d'images `ghcr.io/<user>/<image>` (module 07) |
| **Environments** | secrets par environnement + approbations avant déploiement |
| **Dependabot** | PR automatiques de mise à jour des dépendances / alertes CVE |
| **Secret scanning / push protection** | bloque un push contenant un token reconnu |

**Monorepo vs polyrepo** : ici, un repo pour code + CI (`devops-bootcamp`), un repo séparé pour l'état désiré du cluster (`devops-bootcamp-gitops`). C'est le pattern GitOps recommandé : on sépare **ce qu'on construit** de **ce qui est déployé** (droits d'accès, historique de déploiement lisible, pas de boucle CI infinie).

### 3.8 Authentification

- **HTTPS + token** (Personal Access Token, ou `gh auth login` qui gère tout) ou **SSH** (`ssh-keygen -t ed25519`).
- PAT *classic* (scopes larges) vs *fine-grained* (par repo, par permission, à privilégier… sauf pour GHCR qui exige encore un PAT classic `write:packages`).
- Jamais de token dans une URL commitée, un script ou un Dockerfile.

---

## 4. L'application fil rouge : taskapi

Lis [app/README.md](../app/README.md). Points d'architecture à remarquer **dès maintenant** (on les exploitera tout le bootcamp) :

1. **Configuration par l'environnement** (`config.py`) : aucune URL ni mot de passe en dur.
2. **Deux sondes distinctes** : `/healthz` (le process vit) et `/readyz` (il peut servir : base OK).
3. **Logs JSON sur stdout**, jamais dans un fichier.
4. **Métriques** exposées sur `/metrics` avec des labels à cardinalité maîtrisée.
5. **Arrêt propre** sur SIGTERM (le `lifespan` ferme le pool de connexions).
6. **Application factory** (`create_app`) : testable sans base Postgres.

---

## 5. Pièges classiques du jour

- ❌ Cloner le repo dans `/mnt/c/Users/...` → lenteur, scripts `^M`, permissions.
- ❌ Oublier de rouvrir le terminal après l'ajout au groupe `docker` → `permission denied ... docker.sock`.
- ❌ `git push --force` sur une branche partagée.
- ❌ Commiter un `.env` : même supprimé ensuite, il reste dans l'historique → considère le secret comme compromis et **révoque-le**.
- ❌ Fichiers en CRLF → `/usr/bin/env: 'bash\r': No such file or directory`. Le `.gitattributes` du repo force LF.

---

## Pour aller plus loin

- [Pro Git (livre gratuit, en français)](https://git-scm.com/book/fr/v2) — chapitres 3 (branches) et 10 (internes)
- [Learn Git Branching](https://learngitbranching.js.org/?locale=fr_FR) — exercices visuels sur rebase/cherry-pick
- [Documentation WSL](https://learn.microsoft.com/fr-fr/windows/wsl/)
- [The Twelve-Factor App](https://12factor.net/fr/)
