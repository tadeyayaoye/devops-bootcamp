# Module 16 — Orchestration des mises en production avec XL Release (Digital.ai Release)

> **Objectif** : comprendre ce qu'est l'**orchestration de release** et pourquoi les banques l'utilisent au-dessus de leur CI/CD, maîtriser les objets de XL Release (templates, phases, tâches, gates, variables, équipes), l'intégrer à Jenkins, porter les contrôles (approbations, gel, séparation des tâches) et le piloter **as code** (YAML, API).
>
> **Durée** : cours ~1 h 30 · labs ~3 h · quiz 30 min

> ⚖️ **Licence** : XL Release est un produit **commercial** de Digital.ai. L'image Docker officielle démarre avec une **licence d'essai de 7 jours** (10 utilisateurs max) : fais ce module **d'une traite** dans la semaine où tu lances le conteneur. L'essentiel (concepts, YAML, API) reste valable après.

---

## 1. Pourquoi un orchestrateur de release ?

Le pipeline CI/CD (Jenkins, GitHub Actions, Argo CD) sait **construire et déployer** une application. Une mise en production bancaire, c'est beaucoup plus :

```
 RFC approuvée ? ── CAB ── gel des MEP ? ── build Jenkins ── quality gate ── déploiement recette
      │                                                                          │
   ServiceNow                                                     tests de non-régression (équipe QA)
                                                                                 │
 validation métier (MOA) ── go/no-go ── maintenance Zabbix ── déploiement prod (5 applis, dans l'ordre)
      │                                                                          │
  signature                                          batch Control-M suspendu pendant la MEP, puis relancé
                                                                                 │
                               tests post-MEP ── fermeture RFC ── communication ── rapport d'audit
```

Des **humains** (approbations, validations, tests manuels), des **outils** hétérogènes (ServiceNow, Jenkins, XL Deploy, Ansible, Control-M, Zabbix, Jira…), **plusieurs applications** à livrer ensemble et dans l'ordre, des **règles** (gel, séparation des tâches) et une **traçabilité totale** pour l'audit.

Un **orchestrateur de release** (*Release Orchestration*, *ARO*) modélise ce processus de bout en bout, l'automatise là où c'est possible, et le **trace** partout ailleurs.

| Outil | Rôle |
|---|---|
| **Digital.ai Release** (ex-**XL Release**, XebiaLabs) | orchestration de release : le « chef d'orchestre » |
| **Digital.ai Deploy** (ex-**XL Deploy**) | déploiement d'applications (modèle « package → environnement »), complémentaire |
| Alternatives | ServiceNow DevOps, Octopus Deploy, Harness, CloudBees CD/RO, GitLab Releases + environments, ou des pipelines Jenkins/GitHub avec environnements protégés |

On dit encore très souvent « **XLR** » et « **XLD** » dans les équipes.

---

## 2. Architecture

```
  navigateur / API REST / CLI xl ──► Release server (Java, port 5516)
                                         │  ├─ moteur d'exécution des releases
                                         │  ├─ plugins / intégrations (Jenkins, ServiceNow, Jira, Ansible, Control-M…)
                                         │  └─ moteur de scripts (Jython) + « remote runners » (conteneurs)
                                         ▼
                                     base de données (PostgreSQL en production ; H2 embarquée en essai)
```

En production : cluster de serveurs Release, base externe, *remote runners* sur Kubernetes pour exécuter les tâches conteneurisées, SSO (LDAP/OIDC).

---

## 3. Les objets

| Objet | Description |
|---|---|
| **Folder** | arborescence (par application, par équipe) : droits, variables et connexions héritées |
| **Template** | le **modèle** d'un processus de MEP (réutilisable) |
| **Release** | une **exécution** d'un template (« MEP taskapi 2.3.0 du 14/11 ») — comme DAG / DAG Run, ou Folder / plan actif |
| **Phase** | grande étape séquentielle (Préparation, Build, Recette, Validation, Production, Clôture) |
| **Task** | action unitaire dans une phase ; séquentielle, ou dans un **groupe parallèle** / **groupe séquentiel** |
| **Gate** | **point de contrôle** bloquant : conditions à cocher et/ou dépendances vers d'autres releases ; le *go/no-go* |
| **Variables** | `${version}`, `${rfc}`… : saisies au démarrage, calculées par des tâches (sorties), ou globales ; type *password* pour les secrets (masqués) |
| **Teams / permissions** | qui peut créer, démarrer, réaliser telle tâche, valider telle gate → **séparation des tâches** |
| **Owner / assignee** | chaque tâche manuelle est assignée à une personne ou une équipe |
| **Triggers** | démarrer une release automatiquement (événement Git, planification, webhook) |
| **Release calendar** | vue de toutes les releases planifiées + **blackout periods** (gel des MEP) |
| **Dashboards, risque** | tableaux de bord, score de risque calculé (retards, échecs) |
| **Release groups / Deliveries** | coordonner **plusieurs** releases (une livraison multi-applications, un *release train*) |

### Types de tâches courants

| Tâche | Usage |
|---|---|
| **Manual** | action humaine à cocher (« vérifier le tableau de bord », « prévenir le support ») |
| **Gate** | contrôle bloquant avec conditions / approbations |
| **User input** | demander une valeur en cours de route (ex. le tag d'image) |
| **Notification** | mail aux équipes |
| **Jenkins: Build** | lancer un job Jenkins et attendre son résultat (variables de sortie : numéro de build…) |
| **Webhook / HTTP request** | appeler une API REST (ServiceNow, Zabbix, GitHub…) |
| **Script (Jython)** | logique personnalisée |
| **Plugins** | ServiceNow (créer/attendre l'approbation d'un *change request*), Jira, Ansible, Terraform, Kubernetes, **Control-M** (ordonnancer/hold un folder), XL Deploy… |
| **Create release** | démarrer une autre release (sous-processus) |

### États

Une release : *Planned → In progress → Completed / Aborted* (avec *Failing/Failed* si une tâche échoue).
Sur une tâche en échec : **Retry**, **Skip** (avec commentaire obligatoire : traçabilité !), **Reassign**, ou **Abort** de la release.

---

## 4. Ce qu'XL Release apporte à une banque

- **Traçabilité / audit** : qui a démarré, qui a validé quelle gate, quand, avec quel commentaire, combien de temps chaque étape a pris → **rapport d'audit** exportable.
- **Séparation des tâches** : l'équipe qui développe ne peut pas valider la gate de production ; seuls les membres de l'équipe *Approbateurs CAB* le peuvent.
- **Gel des MEP** : *blackout periods* dans le calendrier ; une release qui tombe dedans est bloquée ou signalée.
- **Standardisation** : un template unique « MEP standard » pour 200 applications → chaque MEP suit le même processus contrôlé, condition pour classer les changements en **standard** (module 13).
- **Orchestration multi-outils et multi-applications** : l'ordre des MEP, les dépendances, les outils historiques (Control-M, XL Deploy, scripts) **et** modernes (Jenkins, Argo CD via un commit Git).
- **Visibilité** : tableau de bord de toutes les MEP de la semaine, retards, risques.

### Et le GitOps dans tout ça ?

Ils se complètent : Argo CD fait le **déploiement** (état désiré dans Git, réconciliation), XL Release orchestre le **processus** autour (approbations, communication, maintenances, batch, multi-applis), et peut **déclencher** la promotion GitOps (créer/merger la PR `envs/prod`). C'est exactement le lab final de ce module.

---

## 5. As code

### Release as code (YAML)

Templates, folders, variables, connexions… s'exportent et s'importent en **YAML** avec le CLI `xl` :

```yaml
apiVersion: xl-release/v1
kind: Templates
spec:
  - name: Livraison taskapi
    type: xlrelease.Release
    variables:
      - type: xlrelease.StringVariable
        key: version
        requiresValue: true
    phases:
      - name: Build
        tasks:
          - name: Construire et scanner l'image
            type: jenkins.Build
            jenkinsServer: Jenkins bootcamp
            jobName: taskapi/main
      - name: Validation
        tasks:
          - name: Go / No-Go CAB
            type: xlrelease.GateTask
            team: Approbateurs CAB
```

```bash
xl apply -f livraison-taskapi.yaml          # crée / met à jour dans le serveur Release
xl generate xl-release -t "<chemin du template>" -f export.yaml   # exporter l'existant en YAML
```

> 💡 Le plus fiable pour apprendre le format exact : construire le template dans l'UI, puis l'**exporter** (bouton *Export* / *Release as code*), le versionner, et le rejouer avec `xl apply`. C'est ce que fait le lab.

### API REST

```bash
curl -u admin:… http://localhost:5516/api/v1/templates                                  # lister les templates
curl -u admin:… -X POST -H 'Content-Type: application/json' \
  http://localhost:5516/api/v1/templates/<id-du-template>/start \
  -d '{"releaseTitle":"MEP taskapi 1a2b3c4","variables":{"version":"1a2b3c4"}}'          # démarrer une release
```

Ainsi Jenkins (ou GitHub Actions) peut **démarrer une release XLR** à la fin d'un build réussi : la CI construit, XLR orchestre la MEP.

---

## 6. Correspondances avec ce que tu connais

| XL Release | Ailleurs dans le bootcamp |
|---|---|
| Template / Release | Jenkinsfile / build ; DAG / DAG run ; folder Control-M / plan actif |
| Phase / Task | stage / step |
| Gate avec approbation d'une équipe | revue obligatoire d'une PR GitOps `envs/prod` ; environnement protégé GitHub |
| Variables `${…}` | paramètres Jenkins, values Helm |
| Blackout period | gel des MEP (module 13), *sync windows* Argo CD (module 08) |
| Skip avec commentaire | *Set to OK* Control-M, *Mark success* Airflow — toujours tracés |
| Rapport d'audit | historique Git + logs CI + historique Argo CD, réunis en un seul endroit |

---

## Pièges classiques

- Mettre **tout** le processus en tâches manuelles : XLR devient une checklist chère. Automatiser tout ce qui peut l'être, garder l'humain pour les **décisions**.
- Mettre des secrets en variables texte : utiliser les variables *password* et les connexions (*Shared configuration*).
- Un template par application, tous différents → impossible à maintenir. Un template standard + variables + folders.
- Laisser les templates uniquement dans l'UI : les exporter en YAML et les versionner.
- *Skip* sans commentaire : l'audit le relèvera.

---

## Pour aller plus loin

- [Digital.ai Release — documentation](https://docs.digital.ai/release/docs/)
- [Installer l'essai Docker](https://docs.digital.ai/release/docs/how-to/install-xl-release-as-a-trial)
- [Release as code / CLI xl](https://docs.digital.ai/release/docs/) (section *As code*)
