# Module 07 — Labs qualité, DevSecOps, GitHub Actions

> ⏱ ~3 h · Prérequis : Jenkins du module 06 opérationnel. SonarQube consomme ~3 Go : arrête le cluster si la RAM manque (`make tf-destroy`, tu le recréeras demain).

---

## Lab 7.1 — Démarrer et configurer SonarQube (≈ 25 min)

```bash
sysctl vm.max_map_count          # doit valoir 524288 (réglé par le bootstrap)
make sonar-up                    # = docker compose -f ci/compose.yaml --profile sonar up -d sonarqube sonar-db
docker logs -f sonarqube         # attends "SonarQube is operational"
```

Configure-le **par l'API** plutôt qu'en cliquant (écris `ci/scripts/sonar-setup.sh`, ou utilise la solution) : changer le mot de passe admin, créer le webhook `http://jenkins:8080/sonarqube-webhook/`, générer un token d'analyse et l'écrire dans `ci/.env` sans l'afficher.

```bash
read -rs SONAR_ADMIN_PASSWORD && export SONAR_ADMIN_PASSWORD     # choisis-en un (12+ caractères)
bash ci/scripts/sonar-setup.sh
docker compose -f ci/compose.yaml up -d jenkins                  # recrée Jenkins avec le nouveau token
```

Connecte-toi sur http://localhost:9000 et explore : *Quality Profiles* (Python → Sonar way), *Quality Gates* (Sonar way : conditions sur le **nouveau code**), *Administration → Webhooks*.

---

## Lab 7.2 — Première analyse à la main (≈ 25 min)

Écris `app/sonar-project.properties` (projectKey `taskapi`, sources `src`, tests `tests`, version Python, chemins des rapports de couverture et de tests).

```bash
cd app && source .venv/bin/activate
mkdir -p reports && pytest --junitxml=reports/junit.xml --cov --cov-report=xml -q
TOKEN=$(grep ^SONAR_TOKEN= ../ci/.env | cut -d= -f2-)
docker run --rm --network cicd -v "$PWD:/usr/src" -e SONAR_HOST_URL=http://sonarqube:9000 -e SONAR_TOKEN="$TOKEN" \
  sonarsource/sonar-scanner-cli
unset TOKEN; cd ..
```

Dans l'UI : couverture, issues, hotspots, duplications. La couverture est-elle importée ? (Si 0 % : les chemins du `coverage.xml` ne correspondent pas — c'est LE problème classique ; ici `/usr/src` vs `app/`… compare avec l'analyse depuis Jenkins au lab suivant, où les chemins sont identiques.)

**Dégrade la qualité volontairement** sur une branche `test/qualite` : ajoute dans `routes.py` une fonction dupliquée non testée, une comparaison `== None`, un `except: pass`. Nous verrons au lab 7.3 la quality gate échouer.

---

## Lab 7.3 — Pipeline qualité + sécurité dans Jenkins (≈ 50 min)

Fais évoluer ton `Jenkinsfile` :

1. Variables d'images d'outils **épinglées** : `aquasec/trivy:0.69.3`, `hadolint/hadolint:v2.12.0`, `ghcr.io/gitleaks/gitleaks:v8.24.0`.
2. Stage **Préparation** : détecte si SonarQube est démarré (`curl http://sonarqube:9000/api/system/status`) → `env.SONAR_UP` ; sinon `unstable(…)`.
3. Stage **Contrôles statiques** en `parallel` : gitleaks (`dir /repo`, en tant que l'utilisateur Jenkins) et hadolint (`< app/Dockerfile`).
4. Stage **Analyse SonarQube** (agent `sonarsource/sonar-scanner-cli`, `args '--network cicd --entrypoint='`, `reuseNode true`, dans `dir('app')` + `withSonarQubeEnv('sonarqube')`).
5. Stage **Quality Gate** : `waitForQualityGate abortPipeline: true` avec un timeout.
6. Stage **Scan image** après le build : rapport HIGH/CRITICAL, *gate* `CRITICAL --ignore-unfixed --exit-code 1`, SBOM CycloneDX archivé (`archiveArtifacts … fingerprint: true`).

Pousse sur `main`, observe le build. Puis pousse ta branche `test/qualite` : la **quality gate doit faire échouer** le pipeline (si « Sonar way » ne bloque pas, crée une gate plus stricte : *Quality Gates → Create* → couverture du nouveau code ≥ 90 %, puis *Set as default*).

**Secret fuité (exercice de réflexe)** sur une branche jetable :

```bash
git switch -c test/fuite
# un faux token au format GitHub, généré à la volée (on n'écrit jamais de vrai secret, même pour tester)
echo "LEAKED = \"ghp_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)\"" >> app/src/taskapi/config.py
gitleaks dir . --no-banner --redact; echo "exit=$?"      # détecté en local d'abord
git commit -am "test: fuite volontaire" && git push -u origin test/fuite
```

Le stage gitleaks de Jenkins doit échouer (et GitHub peut même refuser le push : *push protection*). Supprime la branche (`git push origin --delete test/fuite`). En vrai : le secret est **compromis dès le push** → révocation immédiate, même si la branche est supprimée.

**CVE bloquante** : sur une branche, ajoute `pyyaml==5.3` dans `requirements.txt` (CVE-2020-14343, CRITICAL, corrigée en 5.4) et pousse. Le gate Trivy bloque. Retire-la.

---

## Lab 7.4 — Publication sur GHCR (≈ 20 min)

1. Crée un **token classic** GitHub (scopes `repo` + `write:packages`, expiration 30 j) et mets-le dans `ci/.env` (`GITHUB_TOKEN=`). Recrée Jenkins (`docker compose -f ci/compose.yaml up -d jenkins`).
2. Ajoute le stage **Publication GHCR** (`when { branch 'main' }`, `withCredentials(usernamePassword(…'github-token'…))`, `docker login --password-stdin`, push du tag SHA et du tag `main`, digest archivé, `docker logout` en `post`).
3. Pousse sur `main`. Sur GitHub → *Packages* → `taskapi` : vérifie les tags, passe le package en **Public** si ce n'est pas déjà fait (module 01).

```bash
docker pull ghcr.io/tadeyayaoye/taskapi:main && docker image inspect ghcr.io/tadeyayaoye/taskapi:main --format '{{index .RepoDigests 0}}'
```

---

## Lab 7.5 — Le même pipeline en GitHub Actions (≈ 40 min)

```bash
gh auth refresh -s workflow          # autorise gh à pousser des fichiers .github/workflows
mkdir -p .github/workflows
```

Écris `.github/workflows/ci.yml` avec 3 jobs :
- `secrets` : checkout avec `fetch-depth: 0`, gitleaks en mode `git` (tout l'historique) ;
- `test` : `setup-python` avec cache pip, ruff (`--output-format=github`), pytest, upload des rapports ;
- `image` (`needs: [secrets, test]`, `permissions: packages: write`) : hadolint, buildx, build chargé localement avec cache `type=gha`, scan Trivy épinglé, SBOM, login GHCR **avec `GITHUB_TOKEN`**, push du tag `gha-<sha7>` sur `main` uniquement.

Avec `permissions: contents: read` au niveau du workflow et `concurrency`.

**Épingle les actions par SHA** :

```bash
./scripts/pin-actions.sh .github/workflows/ci.yml      # écris-le ou récupère la solution
git diff .github/workflows/ci.yml
```

Pour que le workflow puisse pousser dans le package créé par Jenkins : *Package settings → Manage Actions access → Add repository → devops-bootcamp → rôle Write*.

```bash
git add .github && git commit -m "ci: pipeline GitHub Actions" && git push
gh run watch
gh run view --log-failed     # si échec
```

Ajoute `.github/dependabot.yml` (pip, docker, github-actions) et observe dans quelques heures/jours les PR proposées.

**Compare** Jenkins et Actions : durée, lisibilité, gestion des secrets, ce que chacun ne peut pas faire ici (Actions n'atteint pas SonarQube local ; Jenkins n'a pas de runners gratuits gérés…).

---

## 🏁 Challenge (sans guide)

1. **Signature keyless** : dans GitHub Actions, après le push, signe l'image avec cosign (`sigstore/cosign-installer`, `permissions: id-token: write`, `cosign sign --yes ghcr.io/…@<digest>`), puis vérifie-la localement avec `cosign verify --certificate-identity-regexp … --certificate-oidc-issuer https://token.actions.githubusercontent.com`.
2. **pre-commit** : ajoute un `.pre-commit-config.yaml` (ruff, gitleaks, hadolint, terraform fmt) et installe le hook (`pipx install pre-commit && pre-commit install`). Le secret du lab 7.3 doit être bloqué **avant** le commit.
3. **SonarQube Cloud** (gratuit pour les repos publics) : connecte ton repo et ajoute l'analyse au workflow Actions pour avoir la décoration des PR.

---

## ✅ Validation

```bash
make check-07
```
