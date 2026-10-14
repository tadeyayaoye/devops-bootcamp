# Module 07 — Qualité, DevSecOps et GitHub Actions

> **Objectif** : intégrer la qualité du code (SonarQube, quality gate) et la sécurité de la chaîne d'approvisionnement logicielle (secrets, dépendances, images, SBOM, signature) dans le pipeline, publier l'image sur un registre, et savoir écrire le même pipeline en **GitHub Actions**.
>
> **Durée** : cours ~1 h 45 · labs ~3 h · quiz 30 min

---

## 1. Shift left : la qualité et la sécurité au plus tôt

```
coût de correction d'un défaut
   ▲
   │                                                    ●  production
   │                                       ●  recette
   │                         ●  CI
   │            ●  revue de code / PR
   │  ●  IDE / pre-commit
   └──────────────────────────────────────────────────────────►  temps
```

Plus un problème est détecté tôt, moins il coûte. D'où des contrôles **automatiques** à chaque étape :

| Étape | Contrôles |
|---|---|
| Poste du dev | linter, formatage, hooks `pre-commit` (gitleaks, ruff…) |
| PR / CI | tests + couverture, **SAST** (analyse statique : SonarQube, Semgrep, CodeQL), **SCA** (dépendances vulnérables), **secrets**, lint Dockerfile/IaC |
| Build | scan de l'image, **SBOM**, signature, provenance |
| Déploiement | admission (Kyverno/Gatekeeper : image signée ? registre autorisé ?), DAST (OWASP ZAP) en recette |
| Production | scan continu (nouvelles CVE sur des images déjà déployées), runtime security (Falco) |

### La pyramide des tests

```
            ▲  e2e / UI          lents, fragiles, peu nombreux
           ▲▲▲  intégration       (API + base réelle, conteneurs de test)
         ▲▲▲▲▲▲▲  unitaires        rapides, nombreux, isolés
```

**Couverture de code** : le % de lignes/branches exécutées par les tests. Utile pour trouver le code non testé, mais **100 % de couverture ≠ code correct** (on peut exécuter une ligne sans vérifier son résultat). Les équipes visent plutôt une couverture élevée **sur le code nouveau**.

---

## 2. SonarQube

### Concepts

| Notion | Sens |
|---|---|
| **Projet** | une base de code analysée (`sonar.projectKey`) |
| **Règles / Quality Profile** | l'ensemble de règles appliquées par langage (« Sonar way » par défaut) |
| **Issues** | *Bugs* (fiabilité), *Vulnerabilities* (sécurité), *Code Smells* (maintenabilité) ; + *Security Hotspots* à revoir manuellement |
| **Métriques** | couverture, duplications, dette technique, complexité, notes A→E |
| **Quality Gate** | ensemble de conditions **bloquantes** (ex. « sur le nouveau code : couverture ≥ 80 %, 0 nouveau bug, duplications < 3 %, hotspots revus ») |
| **Clean as You Code** | la gate porte sur le **nouveau code** : on ne bloque pas une équipe sur 10 ans de dette, mais on interdit d'en ajouter |

### Fonctionnement de l'analyse

```
 Jenkins                     sonar-scanner                    SonarQube
   │ withSonarQubeEnv  ───►  analyse locale du code   ───►    Compute Engine (tâche
   │                         + import couverture/tests         en arrière-plan)
   │                         → .scannerwork/report-task.txt        │
   │ waitForQualityGate  ◄───────────── webhook ───────────────────┘  "OK" / "ERROR"
```

1. Le **scanner** (CLI, Maven, Gradle, .NET) analyse le code **sur l'agent CI** et envoie un rapport.
2. Le serveur le traite de façon **asynchrone**.
3. Le serveur appelle le **webhook** Jenkins (`/sonarqube-webhook/`) ; `waitForQualityGate` récupère alors le statut et **fait échouer le pipeline** si la gate est rouge.

La couverture n'est **pas calculée par Sonar** : il importe le rapport produit par tes tests (`coverage.xml` pour Python, JaCoCo pour Java, lcov pour JS).

### Éditions

**Community Build** (gratuite, notre choix) : analyse de la branche principale uniquement, pas de décoration de PR. Les éditions payantes ajoutent branches/PR, plus de langages et de règles de sécurité. **SonarQube Cloud** (ex-SonarCloud) est gratuit pour les projets publics. Alternatives : Semgrep, CodeQL (gratuit sur les repos publics GitHub), Codacy, DeepSource.

---

## 3. Sécurité de la supply chain logicielle

Ton application, c'est **10 % de ton code et 90 % de code tiers** (dépendances, image de base, actions CI, plugins). Les attaques ciblent de plus en plus ce maillon.

### 3.1 Les attaques qui ont marqué

| Année | Incident | Leçon |
|---|---|---|
| 2020 | **SolarWinds** : build compromis, mise à jour signée piégée | sécuriser la chaîne de build elle-même |
| 2021 | **Log4Shell** : CVE critique dans une lib omniprésente | savoir en minutes où une lib est utilisée → SBOM |
| 2021 | **Codecov** : script de CI modifié → vol de secrets CI | ne pas exécuter de scripts distants non vérifiés |
| 2024 | **xz-utils** : backdoor introduite par un mainteneur infiltré pendant 2 ans | même l'open source « de confiance » peut être compromis |
| 2025 | **tj-actions/changed-files** : tags d'une action GitHub réécrits → secrets de milliers de repos exposés | **épingler les actions par SHA** |
| **mars 2026** | **Trivy** : identifiants volés → binaire 0.69.4 et images 0.69.4-0.69.6 piégés, 76 des 77 tags de `trivy-action` et tous ceux de `setup-trivy` réécrits pour voler les secrets CI (CVE-2026-33634) | même un **outil de sécurité** est une dépendance : épingler (SHA/digest), vérifier, moindre privilège, surveiller les avis |

### 3.2 Les contrôles

| Type | Ce qu'il détecte | Outils (gratuits) |
|---|---|---|
| **Secrets** | clés, tokens, mots de passe dans le code ou l'historique Git | **gitleaks**, trufflehog, GitHub push protection |
| **SCA** (Software Composition Analysis) | dépendances avec CVE connues | **Trivy**, Grype, pip-audit, OSV-Scanner, Dependabot, Renovate |
| **Image** | CVE des paquets OS + librairies de l'image | **Trivy**, Grype, Docker Scout |
| **IaC / config** | Dockerfile, Terraform, manifests K8s mal configurés | **hadolint**, Trivy config, Checkov, kube-linter |
| **SAST** | failles dans TON code (injection SQL, XSS…) | SonarQube, Semgrep, CodeQL, Bandit |
| **DAST** | failles sur l'appli qui tourne | OWASP ZAP |

### 3.3 Lire et trier des vulnérabilités

- **CVE** : identifiant d'une vulnérabilité. **CVSS** : score de gravité 0-10 (LOW/MEDIUM/HIGH/CRITICAL). **EPSS** : probabilité d'exploitation dans les 30 jours. **KEV** (CISA) : liste des CVE **activement exploitées** → priorité absolue.
- Questions à se poser : un **correctif existe-t-il** ? Le composant est-il **atteignable** dans notre usage ? Est-il exposé ?
- Politique raisonnable de *gate* : bloquer sur **CRITICAL corrigeables** (`--severity CRITICAL --ignore-unfixed --exit-code 1`), suivre le reste en tickets, exceptions documentées et datées (`.trivyignore` avec justification).
- Les CVE **apparaissent après coup** : une image saine aujourd'hui sera vulnérable demain → rebuild réguliers et scan continu des images déployées (Trivy Operator, scan du registre).

### 3.4 SBOM, signature, provenance

- **SBOM** (SPDX ou CycloneDX) : inventaire de ce que contient l'artefact → réponse immédiate à « sommes-nous concernés par la CVE X ? ». Exigé par le *Cyber Resilience Act* européen.
- **Signature** avec **cosign** (Sigstore) : prouver que l'image vient bien de ta CI. Mode *keyless* : identité OIDC de la CI (GitHub Actions) + certificat éphémère + journal de transparence (Rekor).
- **Provenance / attestations** (SLSA) : « cette image a été construite à partir de ce commit, par ce workflow ». **SLSA** définit des niveaux de garantie de la chaîne de build.
- **Vérification à l'admission** : Kyverno / policy-controller refusent les images non signées dans le cluster.

### 3.5 Hygiène des secrets en CI

- Tokens **à durée courte et portée minimale** ; idéalement **OIDC** (la CI échange son identité contre un jeton cloud temporaire : plus aucun secret stocké).
- Permissions du `GITHUB_TOKEN` restreintes (`permissions:`).
- Secrets jamais affichés, jamais dans des artefacts, jamais passés à des PR de forks.
- En cas de doute (incident d'outil, fuite) : **rotation immédiate**.

---

## 4. Registres d'images : GHCR

- Adresse : `ghcr.io/<owner>/<image>:<tag>`. Authentification : PAT *classic* `write:packages` (Jenkins) ou **`GITHUB_TOKEN`** avec `permissions: packages: write` (Actions, recommandé).
- Visibilité : privée par défaut → passer en **public** pour un pull anonyme (kind/Argo CD).
- Lier le package au repo : label `org.opencontainers.image.source`. Donner aux workflows du repo l'accès en écriture : *Package settings → Manage Actions access*.
- Toujours noter le **digest** (`sha256:…`) de ce qu'on publie : c'est l'identité réelle de l'image.

---

## 5. GitHub Actions

### Modèle

```
Workflow (.github/workflows/ci.yml)   déclenché par un événement (push, pull_request, schedule, workflow_dispatch…)
 └── Jobs   (en parallèle par défaut ; needs: pour l'ordre)   chacun sur un runner neuf
      └── Steps  (séquentiels)  : run: (shell)  ou  uses: (action réutilisable)
```

| Notion | À retenir |
|---|---|
| **Runner** | VM éphémère hébergée par GitHub (`ubuntu-latest`) — gratuit et illimité pour les repos publics ; ou *self-hosted* (attention sécurité sur repo public !) |
| **Action** | brique réutilisable (`actions/checkout`, `docker/build-push-action`…) : c'est du **code tiers exécuté avec tes secrets** |
| **Contextes** | `${{ github.sha }}`, `${{ secrets.X }}`, `${{ env.X }}`, `${{ matrix.python }}` |
| **`GITHUB_TOKEN`** | jeton éphémère par run, permissions réglables par workflow/job |
| **Cache** | `actions/cache`, `setup-python … cache: pip`, cache BuildKit `type=gha` |
| **Artefacts** | `actions/upload-artifact` (rapports, SBOM) |
| **Matrix** | tester sur plusieurs versions/OS en parallèle |
| **Environments** | secrets par environnement + **règles de protection** (approbation, délai, branches autorisées) |
| **Réutilisation** | *reusable workflows* (`workflow_call`) et *composite actions* |
| **`concurrency`** | annuler les runs obsolètes, sérialiser les déploiements |
| **OIDC** | `permissions: id-token: write` → jetons cloud temporaires, signature keyless |

### Sécurité des workflows

1. **Épingler les actions tierces par SHA complet** (`uses: owner/action@<40 hex> # v1.2.3`) — un tag peut être réécrit (tj-actions 2025, trivy-action 2026). Dependabot sait mettre à jour les SHA.
2. `permissions:` minimal au niveau du workflow, élargi job par job.
3. Ne jamais interpoler directement des données contrôlées par l'utilisateur dans `run:` (`${{ github.event.pull_request.title }}` → injection de commandes) : passer par une variable d'environnement.
4. `pull_request_target` et runners self-hosted sur repo public : très dangereux.
5. Préférer `GITHUB_TOKEN`/OIDC aux PAT longue durée.

### Jenkins ↔ GitHub Actions : correspondances

| Jenkins | GitHub Actions |
|---|---|
| Jenkinsfile | `.github/workflows/*.yml` |
| stage | job (ou step) |
| `agent { docker { image … } }` | `runs-on` + `container:` ou actions setup-* |
| credentials store | secrets / variables / environments |
| `when { branch 'main' }` | `if: github.ref == 'refs/heads/main'` |
| `parallel` | jobs sans `needs` |
| shared library | reusable workflow / composite action |
| `input` | environment avec reviewers requis |
| `archiveArtifacts` | `upload-artifact` |

**Limite clé pour notre labo** : les runners GitHub sont sur Internet, ils ne voient **ni ton SonarQube local, ni ton cluster kind**. Ils peuvent construire et publier l'image ; le **déploiement** se fera en **pull** par Argo CD (module 08). C'est exactement l'argument principal du GitOps.

---

## Pièges classiques

- Quality gate sur le code global au lieu du nouveau code → bloquée en permanence, équipe qui la désactive.
- Scanner sans *gate* (rapport que personne ne lit) ou *gate* trop stricte (HIGH non corrigeables → contournements).
- Couverture non importée dans Sonar (chemin du rapport faux, chemins de fichiers différents entre l'étape de test et l'analyse).
- Actions/outils épinglés par tag mobile (`@v1`, `:latest`).
- PAT avec tous les scopes, sans expiration, partagé entre outils.
- Image publiée en privé → `ImagePullBackOff` côté cluster.

---

## Pour aller plus loin

- [SonarQube Community Build — docs](https://docs.sonarsource.com/sonarqube-community-build/)
- [OpenSSF Scorecard](https://securityscorecards.dev/) · [SLSA](https://slsa.dev/) · [Sigstore / cosign](https://docs.sigstore.dev/)
- [GitHub Actions — Security hardening](https://docs.github.com/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Trivy docs](https://trivy.dev/) — et lis l'avis de sécurité de mars 2026 (GHSA / CVE-2026-33634)
