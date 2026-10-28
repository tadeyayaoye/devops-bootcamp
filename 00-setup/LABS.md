# Module 00 — Labs

> ⏱ ~3 h · Prérequis : droits administrateur sur ton PC, ~15 Go d'espace disque libre, un redémarrage possible.

---

## Lab 0.1 — Installer WSL2 + Ubuntu 24.04 (≈ 20 min, redémarrage)

Dans **PowerShell en tant qu'administrateur** (clic droit sur Démarrer → « Terminal (administrateur) ») :

```powershell
wsl --install -d Ubuntu-24.04
```

Redémarre le PC quand c'est demandé. Au redémarrage, une fenêtre Ubuntu s'ouvre : choisis un **nom d'utilisateur Linux** (minuscules, sans espace) et un mot de passe (il servira pour `sudo`).

Vérifie, toujours dans PowerShell :

```powershell
wsl -l -v        # Ubuntu-24.04 doit être en VERSION 2
wsl --version    # version de WSL et du noyau
```

Dans Ubuntu, vérifie que **systemd** est actif :

```bash
cat /etc/wsl.conf          # doit contenir [boot] systemd=true
systemctl is-system-running   # "running" ou "degraded" = OK ; "offline" = systemd absent
```

Si systemd est absent :

```bash
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
```

puis `wsl --shutdown` dans PowerShell et rouvre Ubuntu.

---

## Lab 0.2 — Plafonner les ressources de WSL (≈ 5 min)

Ton PC a 16 Go de RAM : on donne 12 Go max à WSL pour que Windows reste utilisable.

> 💼 Sur le **PC du taff** (8 Go, proxy d'entreprise), suis plutôt [PC-TAFF.md](PC-TAFF.md).

Copie le fichier [wslconfig.example](wslconfig.example) vers `C:\Users\<toi>\.wslconfig` (note le point au début, pas d'extension). Depuis PowerShell :

```powershell
notepad $env:USERPROFILE\.wslconfig     # colle le contenu de wslconfig.example, enregistre
wsl --shutdown
```

Rouvre Ubuntu et vérifie :

```bash
free -h      # total ≈ 11-12 Gi
nproc        # 10
```

---

## Lab 0.3 — Récupérer le bootcamp dans WSL (≈ 10 min)

> ⚠ On travaille **dans `~`**, jamais dans `/mnt/c`.

```bash
sudo apt-get update && sudo apt-get install -y git make
cd ~
git clone https://github.com/tadeyayaoye/devops-bootcamp.git
cd devops-bootcamp
```

Configure ton identité Git (une fois pour toutes) :

```bash
git config --global user.name  "Ton Nom"
git config --global user.email "ton-email@exemple.com"
git config --global init.defaultBranch main
git config --global pull.rebase true          # pull = fetch + rebase (historique linéaire)
git config --global rebase.autoStash true
git config --global push.autoSetupRemote true
git config --global core.autocrlf input       # jamais de CRLF dans les commits
git config --global --list
```

---

## Lab 0.4 — Installer l'outillage (≈ 20 min, surtout de l'attente)

Lis d'abord le script (règle d'or : on n'exécute jamais un script sans l'avoir lu) :

```bash
less scripts/bootstrap-wsl.sh
```

Questions à te poser en le lisant : pourquoi vérifie-t-on des checksums ? Pourquoi Trivy est-il épinglé alors que kubectl prend la dernière version ? Pourquoi `pipx` pour Ansible ?

```bash
./scripts/bootstrap-wsl.sh
```

**Ferme le terminal Ubuntu et rouvre-le** (groupe `docker`), puis :

```bash
cd ~/devops-bootcamp
make tools
docker run --rm hello-world
```

Tout doit être vert. Sinon, relis le message d'erreur : le script est idempotent, tu peux le relancer.

### Connecter GitHub dans WSL

```bash
gh auth login          # GitHub.com → HTTPS → "Login with a web browser"
gh auth setup-git      # git utilisera gh pour s'authentifier en HTTPS
gh auth status
```

> 💡 Il te faudra le scope `workflow` au module 07 (pousser des fichiers `.github/workflows`) : `gh auth refresh -s workflow`.

---

## Lab 0.5 — L'application en local (≈ 30 min)

```bash
make app-venv          # crée app/.venv et installe les dépendances
make app-test          # ruff + pytest + couverture
```

Lis la sortie de couverture : quels fichiers sont les moins couverts, et pourquoi (indice : `telemetry.py`) ?

Lance l'application avec SQLite :

```bash
make app-run           # laisse tourner dans ce terminal
```

Dans un **second terminal** :

```bash
curl -s localhost:8000/ | jq
curl -s localhost:8000/healthz
curl -s localhost:8000/readyz
curl -s -X POST localhost:8000/api/tasks -H 'content-type: application/json' \
     -d '{"title":"réviser Git","description":"rebase, reflog, bisect"}' | jq
curl -s localhost:8000/api/tasks | jq
curl -s localhost:8000/metrics | grep -E '^http_requests_total|^taskapi_'
```

Ouvre http://localhost:8000/docs **dans ton navigateur Windows** : ça marche grâce au *localhost forwarding* de WSL2.

Observe les logs dans le premier terminal : une ligne JSON par requête.

**Expérience signaux** — arrête `make app-run` (Ctrl+C = SIGINT : observe le log `arrêt`), puis lance l'appli **sans** `--reload`, en arrière-plan :

```bash
cd ~/devops-bootcamp/app && source .venv/bin/activate
DATABASE_URL=sqlite:///./taskapi.db PYTHONPATH=src uvicorn taskapi.main:create_app --factory &
sleep 2; pgrep -af uvicorn               # repère le PID
kill -TERM %1                            # log "arrêt" : arrêt propre (le lifespan s'exécute)
DATABASE_URL=sqlite:///./taskapi.db PYTHONPATH=src uvicorn taskapi.main:create_app --factory &
sleep 2; kill -KILL %1                   # aucun log d'arrêt : le noyau a tué le process net
cd ..
```

C'est exactement ce qui arrive à un conteneur qui ne reçoit pas SIGTERM (module 01) : au bout du délai de grâce, SIGKILL.

**Expérience chaos :**

```bash
curl -s -X PUT localhost:8000/chaos -H 'content-type: application/json' -d '{"error_rate":0.5,"latency_ms":300}'
for i in $(seq 10); do curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' localhost:8000/api/tasks; done
curl -s -X PUT localhost:8000/chaos -H 'content-type: application/json' -d '{"error_rate":0,"latency_ms":0}'
```

---

## Lab 0.6 — Git : workflow de PR (≈ 30 min)

```bash
git switch -c feat/progression-j0
# Mets à jour PROGRESSION.md (coche le cours du module 00, note ton niveau "avant")
git add -p                                     # ajoute par morceaux, lis ce que tu ajoutes
git commit -m "docs(progression): démarrage du module 00"
git push
gh pr create --fill --base main
gh pr view --web                               # regarde la PR dans le navigateur
gh pr merge --squash --delete-branch
git switch main && git pull
git log --oneline --graph -5
```

---

## Lab 0.7 — Git : rebase, conflit, reflog, bisect (≈ 45 min)

On s'entraîne dans un repo jetable pour ne rien casser :

```bash
cd /tmp && rm -rf git-lab && mkdir git-lab && cd git-lab && git init -q
printf 'version=1\nport=8000\n' > app.conf && git add . && git commit -qm "init"
git switch -qc feature
sed -i 's/port=8000/port=9000/' app.conf && git commit -qam "feat: port 9000"
echo 'debug=true' >> app.conf && git commit -qam "feat: debug"
git switch -q main
sed -i 's/port=8000/port=8080/' app.conf && git commit -qam "fix: port 8080"
git log --oneline --graph --all
```

**a) Rebase avec conflit**

```bash
git switch feature
git rebase main             # CONFLIT sur app.conf
git status                  # lis bien ce que Git te dit
# Édite app.conf : choisis port=9000, supprime les marqueurs <<<<<<< ======= >>>>>>>
git add app.conf
git rebase --continue
git log --oneline --graph --all     # historique linéaire : feature est "au-dessus" de main
```

**b) Rebase interactif** : fusionne les deux commits de `feature` en un seul.

```bash
git rebase -i main          # remplace "pick" par "squash" (ou "s") sur la 2e ligne
```

**c) Catastrophe et sauvetage**

```bash
git reset --hard HEAD~1     # "oups"
git log --oneline           # le commit a disparu…
git reflog                  # … mais pas pour le reflog
git reset --hard HEAD@{1}   # retour à l'état précédent
```

**d) Bisect** : trouver automatiquement le commit qui a cassé quelque chose.

```bash
cd /tmp && rm -rf bisect-lab && mkdir bisect-lab && cd bisect-lab && git init -q
for i in $(seq 1 20); do echo "ligne $i" >> f.txt; [ $i -eq 13 ] && echo BUG >> f.txt; git add f.txt; git commit -qm "commit $i"; done
git bisect start
git bisect bad HEAD
git bisect good HEAD~19
git bisect run sh -c '! grep -q BUG f.txt'     # Git teste tout seul, par dichotomie
git bisect reset
```

Combien d'étapes a-t-il fallu pour 20 commits ? (Réponse : ~log2(20) ≈ 5.)

---

## 🏁 Challenge (sans guide)

1. Écris un script `scripts/doctor.sh` qui vérifie : que tu n'es pas dans `/mnt/c`, que Docker répond, que la RAM WSL est ≥ 10 Go, que `vm.max_map_count` ≥ 524288, que `git config user.email` est défini. Il doit utiliser `set -euo pipefail` et finir avec un code retour ≠ 0 si un point échoue.
2. Passe-le dans `shellcheck` (`sudo apt install shellcheck`), corrige tous les avertissements.
3. Commite-le via une PR avec un message *Conventional Commits*.

---

## ✅ Validation

```bash
make check-00
```
