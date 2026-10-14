# Module 06 — Labs Jenkins

> ⏱ ~3 h · Tu écris `ci/` (plateforme CI) et `Jenkinsfile` (à la racine du repo).
> RAM : si besoin, arrête le labo Ansible (`docker compose -f 05-ansible/lab/compose.yaml down`). Le cluster peut rester.

---

## Lab 6.1 — Jenkins as Code : image et plugins (≈ 30 min)

```bash
mkdir -p ci/jenkins/casc
```

1. `ci/jenkins/Dockerfile` : à partir de `jenkins/jenkins:lts-jdk21`, installe la **CLI Docker** (dépôt officiel Docker pour Debian), `jq`, et **kustomize** (utile au module 08), puis les plugins depuis `plugins.txt` avec `jenkins-plugin-cli`.
2. `ci/jenkins/plugins.txt` : `configuration-as-code`, `job-dsl`, `workflow-aggregator`, `pipeline-graph-view`, `git`, `docker-workflow`, `credentials-binding`, `timestamper`, `ansicolor`, `ws-cleanup`, `junit`, `coverage`, `sonar`…

```bash
docker build -t bootcamp-jenkins:latest ci/jenkins
docker run --rm bootcamp-jenkins:latest bash -c 'docker --version; kustomize version; ls /usr/share/jenkins/ref/plugins | wc -l'
```

---

## Lab 6.2 — Configuration as Code et lancement (≈ 40 min)

Prépare l'hôte (chemin identique hôte/conteneur, voir le cours § Docker-out-of-Docker) :

```bash
sudo mkdir -p /var/jenkins_home && sudo chown 1000:1000 /var/jenkins_home
```

`ci/.env` (ignoré par Git) à partir de [solutions/ci/.env.example](solutions/ci/.env.example) :

```bash
cp 06-ci-jenkins/solutions/ci/.env.example ci/.env
sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$(getent group docker | cut -d: -f3)/" ci/.env
sed -i "s/^JENKINS_ADMIN_PASSWORD=.*/JENKINS_ADMIN_PASSWORD=$(openssl rand -hex 12)/" ci/.env
grep JENKINS_ADMIN_PASSWORD ci/.env     # note-le
```

Écris :
- `ci/jenkins/casc/jenkins.yaml` : message système, utilisateur `admin` (mot de passe depuis `${JENKINS_ADMIN_PASSWORD}`), stratégie « utilisateurs connectés », credentials `github-token` (usernamePassword) et `sonar-token` (string) avec valeurs par défaut `${VAR:-non-defini}`, URL `http://localhost:8080/`, serveur SonarQube `http://sonarqube:9000`, et un job **multibranch `taskapi`** en Job DSL (source Git = ton repo, `scriptPath('Jenkinsfile')`, scan périodique toutes les 2 min).
- `ci/compose.yaml` : service `jenkins` (build `./jenkins`, port `127.0.0.1:8080`, `env_file`, `group_add: ["${DOCKER_GID}"]`, volumes `/var/jenkins_home` **au même chemin**, socket Docker, `./jenkins/casc` en lecture seule), réseau nommé **`cicd`**. Prépare aussi les services `sonarqube` et `sonar-db` sous le **profil** `sonar` (module 07).

```bash
make ci-up                      # = docker compose -f ci/compose.yaml up -d --build jenkins
docker logs -f jenkins          # attends "Jenkins is fully up and running"
```

Ouvre http://localhost:8080, connecte-toi en `admin`. Vérifie : **aucun assistant d'installation**, le job `taskapi` existe déjà, *Manage Jenkins → Credentials* contient tes deux credentials (valeurs masquées), *Manage Jenkins → Configuration as Code* montre ton YAML.

Expérience « as code » : change le `systemMessage` dans le YAML puis *Reload existing configuration*. Change-le ensuite dans l'UI, puis recharge le YAML : qui gagne ?

---

## Lab 6.3 — Premier Jenkinsfile (≈ 50 min)

Crée `Jenkinsfile` à la racine du repo :

- `agent any`, `options` (timestamps, ansiColor, buildDiscarder, timeout 30 min, disableConcurrentBuilds) ;
- stage **Préparation** : `SHORT_SHA` (`git rev-parse --short=7 HEAD`) dans `env`, `currentBuild.displayName` ;
- stage **Lint & tests** dans un agent **`docker { image 'python:3.12-slim'; reuseNode true }`** : venv, `ruff check`, `pytest` avec JUnit XML et couverture XML ; en `post { always { … } }` : `junit` et `recordCoverage` ;
- stage **Build image** : `docker build` avec `APP_VERSION` et `GIT_SHA`, tag `ghcr.io/tadeyayaoye/taskapi:${IMAGE_TAG}` ;
- stage **Smoke test** : lancer l'image sur le réseau `cicd` avec SQLite, attendre `/readyz` (boucle), toujours supprimer le conteneur en `post` ;
- `post` global : messages succès/échec, `cleanWs`.

```bash
git add Jenkinsfile ci/ && git commit -m "ci: pipeline Jenkins (lint, tests, build, smoke test)" && git push
```

Dans Jenkins : job `taskapi` → *Scan Multibranch Pipeline Now* (ou attends 2 min). Ouvre le build de `main`, regarde la vue graphique (*Pipeline Overview*), les **résultats de tests** et la **couverture**.

Observe dans un terminal ce que fait Jenkins pendant le stage de tests :

```bash
watch -n1 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Command}}"'
```

---

## Lab 6.4 — Casser le pipeline (exprès) (≈ 30 min)

Sur une branche `test/ci-rouge`, introduis successivement (un commit et un push à chaque fois) :

1. une erreur de lint (`import os` inutilisé dans `routes.py`) ;
2. un test qui échoue (change une assertion dans `test_tasks.py`) ;
3. une erreur de Dockerfile (`COPY fichier-inexistant .`) ;
4. une image qui se construit mais dont l'appli ne démarre pas (dans le `ENTRYPOINT` du Dockerfile, remplace `taskapi.main:create_app` par `taskapi.mian:create_app`).

Pour chacun : quel stage est rouge ? Qu'affiche Jenkins (onglet *Tests*, logs) ? Le stage suivant a-t-il été exécuté ? Combien de temps pour le feedback ?

Le multibranch crée automatiquement un job pour ta branche. Supprime-la ensuite (`git push origin --delete test/ci-rouge`) : le job disparaît au scan suivant.

---

## Lab 6.5 — Rendre le pipeline plus rapide et plus sûr (≈ 25 min)

1. **Parallélisme** : sépare « Lint » et « Tests » en deux stages `parallel` (chacun dans son conteneur). Gain ?
2. **Ne pas tout reconstruire** : ajoute `when { changeset "app/**" }` sur les stages coûteux. Pousse un commit qui ne touche que `PROGRESSION.md` : que se passe-t-il ? (Limite : `changeset` compare au build précédent de la branche.)
3. **Secrets** : ajoute un stage de test qui utilise `withCredentials([string(credentialsId: 'sonar-token', variable: 'T')])` et fais `sh "echo ${T}"` (guillemets doubles) puis `sh 'echo "$T"'`. Compare les avertissements et l'affichage (`****`).

---

## 🏁 Challenge (sans guide)

1. **Shared library** : déplace la logique « build + smoke test » dans une bibliothèque partagée `ci/shared-lib/vars/buildAndSmoke.groovy` (`def call(Map args)`), déclarée dans JCasC (`unclassified.globalLibraries`, retriever `modernSCM` avec `libraryPath: 'ci/shared-lib/'`), et appelle-la depuis le Jenkinsfile avec `@Library('bootcamp-lib') _`.
2. **Paramètre** : ajoute un paramètre `SKIP_TESTS` (booléen, défaut `false`) qui saute les tests, mais **interdit** sur `main` (le pipeline doit échouer avec un message clair).
3. **Sauvegarde** : écris un script `ci/backup-jenkins.sh` qui archive `/var/jenkins_home` (sans `workspace/` ni `caches`) en `.tar.gz` horodaté. Pourquoi, avec JCasC + Job DSL, cette sauvegarde est-elle moins critique ? Qu'est-ce qui reste à sauvegarder ?

---

## ✅ Validation

```bash
make check-06
```
