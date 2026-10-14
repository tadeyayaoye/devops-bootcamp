# Module 06 — CI/CD et Jenkins

> **Objectif** : maîtriser les principes de l'intégration et du déploiement continus, comprendre l'architecture de Jenkins, le configurer **entièrement en code** (image, plugins, JCasC, Job DSL) et écrire un Jenkinsfile déclaratif de qualité professionnelle.
>
> **Durée** : cours ~1 h 30 · labs ~3 h · quiz 30 min

---

## 1. CI, CD, CD : de quoi parle-t-on ?

```
 commit ─► build ─► tests ─► analyse ─► artefact ─► déploiement ─► déploiement ─► déploiement
                                         (image)     en dev          en staging      en prod
 └──────── Intégration Continue ────────┘
 └──────────────────── Livraison Continue (prod = bouton manuel) ──────────────────┘
 └──────────────────── Déploiement Continu (prod automatique) ─────────────────────┘
```

| Terme | Définition |
|---|---|
| **Intégration continue (CI)** | chaque changement est intégré à la branche principale **fréquemment** et vérifié automatiquement (build + tests) → détecter les problèmes en minutes |
| **Livraison continue** | chaque changement validé produit un artefact **déployable** en production à tout moment ; la mise en prod est une décision humaine |
| **Déploiement continu** | chaque changement validé part **automatiquement** en production |

### Les principes qui comptent

- **Feedback rapide** : un pipeline de CI doit idéalement tenir en moins de 10 minutes. Mettre les étapes rapides et souvent en échec en premier (*fail fast*).
- **Build once, deploy many** : l'artefact (image) est construit **une seule fois**, puis **le même** est promu d'environnement en environnement. On ne reconstruit jamais pour la prod.
- **Artefacts immuables et traçables** : tag = SHA du commit, métadonnées (labels OCI), SBOM.
- **Pipeline as code** : le pipeline est versionné avec le code (Jenkinsfile, `.github/workflows`, `.gitlab-ci.yml`), revu en PR.
- **Environnements éphémères** : chaque étape tourne dans un environnement propre (conteneur), pas sur une machine « qui a déjà tout installé ».
- **Sécurité** : secrets dans un coffre (credentials store), jamais dans le code ni dans les logs ; moindre privilège.

### Les métriques DORA

Les 4 indicateurs (rapport *Accelerate*, Google DORA) qui mesurent la performance de livraison :

| Indicateur | Élite |
|---|---|
| **Fréquence de déploiement** | à la demande (plusieurs fois par jour) |
| **Délai de mise en production** (commit → prod) | < 1 jour |
| **Taux d'échec des changements** | faible (0-15 %) |
| **Temps de restauration** après incident | < 1 heure |

(Les rapports récents ajoutent un 5ᵉ indicateur sur le *rework*.) Tout le bootcamp va dans ce sens : petits changements, automatisés, rapides à annuler.

---

## 2. Jenkins : architecture

```
                         ┌──────────────── Contrôleur Jenkins ────────────────┐
  Git (polling/webhook) ─►│ UI · API · planification · plugins · credentials   │
                         │ JENKINS_HOME : config, jobs, historiques, plugins   │
                         └───────┬──────────────────────┬──────────────────────┘
                                 │ Remoting (JNLP/SSH)   │ Cloud (à la demande)
                       ┌─────────┴─────┐       ┌────────┴──────────────────────┐
                       │ Agent statique │       │ Agents éphémères              │
                       │ label: linux   │       │ Docker / Pods Kubernetes      │
                       │ N exécuteurs   │       │ créés pour un build, détruits │
                       └───────────────┘       └───────────────────────────────┘
```

| Notion | Sens |
|---|---|
| **Contrôleur** (ex-« master ») | orchestre, stocke la config et l'historique ; ne devrait **pas exécuter de builds** (`numExecutors: 0`) |
| **Agent** (nœud) | machine/conteneur qui exécute les builds ; identifié par des **labels** |
| **Exécuteur** | un « slot » de build sur un nœud |
| **Cloud** | provisionne des agents à la demande : plugin Docker, **plugin Kubernetes** (un pod par build, avec plusieurs conteneurs : `python`, `docker`, `kaniko`…) |
| **Workspace** | dossier de travail d'un build sur un nœud |
| **Plugins** | presque tout est un plugin (Git, Pipeline, Docker, credentials…) : force et faiblesse (mises à jour, compatibilité, CVE) |

Jenkins est **ancien (2011, fork de Hudson)**, très flexible et toujours très présent en entreprise (surtout on-prem et dans les grands groupes). Ses points faibles : maintenance des plugins, contrôleur à état (JENKINS_HOME à sauvegarder), sécurité à surveiller. D'où l'importance de le gérer **as code**.

### Docker dans Jenkins : les options

| Approche | Principe | Remarque |
|---|---|---|
| **Docker-out-of-Docker** (notre labo) | le socket Docker de l'hôte est monté dans Jenkins | simple, mais Jenkins devient root-équivalent sur l'hôte |
| Docker-in-Docker (dind) | un démon Docker dans un conteneur privilégié | isolation moyenne, `--privileged` |
| **Kaniko / BuildKit rootless / Buildah** | construire des images **sans démon ni privilèges** | ✅ recommandé sur Kubernetes |
| Agents Kubernetes | un pod par build | ✅ standard moderne avec Jenkins |

---

## 3. Jenkins as Code

Une installation Jenkins configurée à la main est un *snowflake* impossible à reconstruire. Les 4 couches à mettre en code :

| Couche | Outil |
|---|---|
| Image (version de Jenkins, outils) | `Dockerfile` basé sur `jenkins/jenkins:lts-jdk21` |
| Plugins | `plugins.txt` + `jenkins-plugin-cli` au build de l'image |
| Configuration globale (sécurité, credentials, outils, intégrations) | **JCasC** (Configuration as Code) : YAML, variables `${VAR}` |
| Jobs | **Job DSL** (dans JCasC) ou découverte automatique (Multibranch, Organization Folder) |
| Pipelines | **Jenkinsfile** dans chaque repo |
| Code partagé entre pipelines | **Shared Libraries** |

```yaml
# JCasC (extrait)
jenkins:
  numExecutors: 0
  securityRealm:
    local:
      users: [{ id: admin, password: "${JENKINS_ADMIN_PASSWORD}" }]
credentials:
  system:
    domainCredentials:
      - credentials:
          - string: { id: sonar-token, secret: "${SONAR_TOKEN}" }
```

Les secrets de JCasC viennent de variables d'environnement, de fichiers montés (secrets Kubernetes/Docker) ou d'un coffre (plugin HashiCorp Vault, AWS Secrets Manager…).

---

## 4. Pipelines

### Déclaratif vs scripté

| Déclaratif (`pipeline { … }`) | Scripté (`node { … }`) |
|---|---|
| structure imposée, lisible, validable | Groovy libre |
| `post`, `when`, `options`, `parallel`, `matrix` intégrés | tout à la main |
| ✅ standard aujourd'hui | pour des cas très dynamiques, souvent dans des shared libraries |

On peut injecter du Groovy dans un déclaratif via `script { … }`, avec modération.

### Anatomie d'un Jenkinsfile déclaratif

```groovy
pipeline {
    agent none                                   // ou any, ou { label 'linux' }, ou { docker {…} }, ou { kubernetes {…} }
    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timestamps()
    }
    parameters { booleanParam(name: 'DEPLOY', defaultValue: false) }
    triggers   { pollSCM('H/5 * * * *') }       // pour un job simple ; le multibranch a ses propres triggers
    environment {
        IMAGE = 'ghcr.io/org/app'
        REGISTRY_CREDS = credentials('ghcr')    // injecte REGISTRY_CREDS_USR / _PSW (masqués)
    }
    stages {
        stage('Tests') {
            agent { docker { image 'python:3.12-slim'; reuseNode true } }
            steps { sh 'pytest' }
            post { always { junit 'reports/*.xml' } }
        }
        stage('Qualité') {
            parallel {                           // étapes indépendantes en parallèle
                stage('Lint')  { steps { sh 'ruff check .' } }
                stage('Audit') { steps { sh 'pip-audit' } }
            }
        }
        stage('Déployer') {
            when { allOf { branch 'main'; expression { params.DEPLOY } } }
            input { message 'Déployer en prod ?' }   // validation humaine
            steps { … }
        }
    }
    post {
        always  { cleanWs() }
        failure { /* notifier Slack/Teams/mail */ }
    }
}
```

| Bloc | À retenir |
|---|---|
| `agent` | où s'exécute le pipeline / un stage. `reuseNode true` = même nœud et workspace |
| `environment` | variables ; `credentials('id')` les injecte **masquées** dans les logs |
| `withCredentials([...])` | portée limitée d'un secret à quelques étapes ✅ |
| `when` | `branch`, `changeset 'app/**'`, `tag`, `environment`, `expression`, `allOf/anyOf/not` |
| `post` | `always`, `success`, `failure`, `unstable`, `changed`, `fixed`, `cleanup` |
| `stash`/`unstash` | transférer des fichiers entre nœuds |
| `archiveArtifacts`, `junit`, `recordCoverage` | publier les résultats dans l'UI |

> ⚠ **Interpolation et secrets** : dans `sh "echo ${TOKEN}"` (guillemets doubles), c'est **Groovy** qui interpole → le secret se retrouve dans la ligne de commande (et Jenkins avertit). Utilise des guillemets simples `sh 'echo "$TOKEN"'` : c'est le **shell** qui lit la variable d'environnement.

### Multibranch Pipeline

Un job « dossier » qui scanne le repo, crée **un sous-job par branche** (et par PR avec les plugins GitHub/GitLab Branch Source) contenant un Jenkinsfile, et supprime ceux des branches disparues. Déclenchement : **webhook** (idéal) ou **scan périodique** (notre cas : Jenkins n'est pas joignable depuis GitHub). *Organization Folder* : la même chose pour tous les repos d'une organisation.

### Shared Libraries

```groovy
@Library('bootcamp-lib@main') _
dockerBuildPush(image: 'ghcr.io/org/app', context: 'app')
```

Dossier `vars/` (étapes globales simples, un fichier `nomEtape.groovy` avec `def call(Map args)`), `src/` (classes Groovy), `resources/`. Elles évitent de copier-coller 300 lignes de pipeline dans 50 repos et permettent de faire évoluer les pratiques de façon centralisée (versionnées par tag).

---

## 5. Jenkins vs les autres

| | Jenkins | GitHub Actions | GitLab CI |
|---|---|---|---|
| Hébergement | auto-hébergé | SaaS (runners hébergés ou self-hosted) | SaaS ou auto-hébergé |
| Config | Jenkinsfile (Groovy) | YAML | YAML |
| Extensibilité | ~2000 plugins | Marketplace d'actions | templates, components |
| Maintenance | lourde (contrôleur, plugins) | quasi nulle | moyenne |
| Points forts | flexibilité extrême, on-prem, legacy | intégration GitHub, OIDC cloud | plateforme complète (SCM + CI + registry…) |

Autres : Tekton (CI native Kubernetes), Argo Workflows, CircleCI, Azure DevOps, Buildkite, Dagger (pipelines en code portable).

---

## 6. Bonnes pratiques d'un pipeline

1. **Tout dans des conteneurs** : versions d'outils figées, aucune dépendance sur l'agent.
2. **Fail fast** : lint et tests unitaires d'abord ; tests longs ensuite / en parallèle.
3. **Résultats publiés** (JUnit, couverture, rapports de scan) pour que l'échec soit lisible sans fouiller les logs.
4. **Timeouts** partout, **nettoyage** (`cleanWs`, `docker rm -f` en `post`).
5. Secrets via le credentials store, en portée minimale, jamais affichés.
6. Pipeline **idempotent et rejouable** (relancer un build ne casse rien).
7. Branches : CI complète sur les PR, publication/déploiement uniquement depuis `main` (ou les tags).
8. Le pipeline lui-même est revu en PR et testé (ex. Jenkinsfile Runner, `act` pour GitHub Actions).

---

## Pièges classiques

- Contrôleur avec des exécuteurs et tous les outils installés dessus → impossible à reproduire, risque de sécurité.
- Plugins jamais mis à jour → CVE (Jenkins publie régulièrement des avis de sécurité).
- `sh "… ${secret} …"` → fuite de secret.
- Workspace partagé entre builds sans nettoyage → résultats faux.
- Docker-out-of-Docker : les chemins de volumes sont ceux de l'**hôte**, pas du conteneur Jenkins (d'où notre montage `/var/jenkins_home` au même chemin).
- Builds déclenchés par la CI elle-même (commit du pipeline qui relance le pipeline) → boucles infinies : filtrer par auteur/chemin, ou committer dans un autre repo (GitOps).

---

## Pour aller plus loin

- [Jenkins — Pipeline syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Configuration as Code — démos](https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos)
- [Job DSL API viewer](https://jenkinsci.github.io/job-dsl-plugin/)
- [DORA — Accelerate State of DevOps](https://dora.dev/)
