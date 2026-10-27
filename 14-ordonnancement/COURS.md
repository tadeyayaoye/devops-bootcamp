# Module 14 — L'ordonnancement : concepts, Control-M, et pratique avec Airflow

> **Objectif** : maîtriser les concepts de l'ordonnancement de production (chaînes, conditions, ressources, calendriers, plan de production, reprise), connaître **Control-M** en profondeur (architecture, objets, Jobs-as-Code, exploitation), et les pratiquer **gratuitement** sur une vraie chaîne batch bancaire avec **Apache Airflow**.
>
> **Durée** : cours ~2 h · labs ~3 h 30 · quiz 30 min

> ⚖️ **Pourquoi Airflow pour pratiquer ?** Control-M est un logiciel commercial. BMC propose **Control-M Workbench**, un environnement de développement gratuit en conteneur, mais son téléchargement passe par le portail client BMC (EPD) : tu y auras peut-être accès via ta mission. Airflow est gratuit, open source, très demandé lui aussi, et ses concepts se **traduisent un pour un** vers Control-M (tableau du § 6). Tu écriras aussi la même chaîne en **JSON Control-M** (Jobs-as-Code), pour être opérationnel le jour où tu auras un Workbench.

---

## 1. Pourquoi un ordonnanceur ?

`cron` lance une commande à une heure donnée. C'est tout. En production, il faut beaucoup plus :

| Besoin | cron | Ordonnanceur d'entreprise |
|---|---|---|
| Lancer B **seulement si A a réussi** | ❌ (bricolage) | ✅ dépendances / conditions |
| Attendre l'**arrivée d'un fichier** | ❌ | ✅ file watcher |
| Ne pas lancer 2 jobs qui écrivent dans la même base | ❌ | ✅ ressources |
| « Les jours ouvrés sauf fériés, et le dernier jour du mois » | ❌ | ✅ calendriers |
| Voir l'état de **toute** la production en un écran | ❌ | ✅ moniteur |
| Relancer **à partir de l'étape en échec** | ❌ | ✅ reprise |
| Être alerté si la chaîne **risque de finir en retard** | ❌ | ✅ SLA |
| Exécuter sur **des centaines de serveurs** (Linux, Windows, AIX, mainframe) | ❌ un cron par machine | ✅ agents centralisés |
| Savoir **qui** a relancé quoi, quand | ❌ | ✅ audit |

On parle aussi de **WLA** (*Workload Automation*) ou de **SOAP** (*Service Orchestration and Automation Platform*, terme Gartner).

---

## 2. Les concepts universels

Ces notions existent dans **tous** les ordonnanceurs, sous des noms différents. Si tu les maîtrises, changer d'outil est facile.

### 2.1 Job, chaîne, plan

- **Job** (traitement, tâche) : une unité d'exécution — un script, une commande, un programme, un transfert de fichier, un appel d'API, une requête SQL, un job mainframe (JCL).
- **Chaîne** (*folder* chez Control-M, *session* chez $U, *application* chez VTOM, *DAG* chez Airflow) : un ensemble de jobs liés qui forment un traitement métier (« arrêté comptable »).
- **Définition** vs **exécution** : la définition est le modèle (« ce job tourne les jours ouvrés à 22 h »), l'exécution est une instance concrète (« le job du 27/10 »).
- **Plan de production** : l'ensemble des exécutions prévues pour une journée de production.

### 2.2 La journée de production et la date d'ordonnancement

C'est **LA** notion qui déroute au début :

```
       journée de production du 27/10 (ODATE = 20261027)
  ├───────────────────────────────────────────────────────────┤
 27/10 06:00 (« New Day »)                           28/10 05:59
```

- Une **journée de production** ne commence pas forcément à minuit : souvent à 6 h, 7 h… (heure de « New Day » / « bascule »).
- Chaque exécution porte une **date d'ordonnancement** (ODATE chez Control-M, *date de traitement* chez $U, *logical date* chez Airflow) = la **date métier** qu'elle traite, pas forcément la date réelle d'exécution. Le job « arrêté du 27 » qui tourne à 2 h du matin le 28 a l'ODATE du 27.
- Conséquence : les fichiers, les tables, les logs sont nommés avec l'ODATE (`transactions_20261027.csv`), et **relancer un job d'hier** traite les données d'hier.

### 2.3 Dépendances

| Type | Exemple |
|---|---|
| **Séquence** dans une chaîne | contrôle → chargement → calcul |
| **Conditions** (événements) entre chaînes ou applications | « le reporting attend que l'arrêté comptable ait posé la condition `ARRETE-OK` » |
| **Fichier** | attendre `transactions_20261027.csv` |
| **Horaire** | pas avant 22 h (*from time*), pas après 5 h (*until*) |
| **Ressource** | voir ci-dessous |
| **Manuelle** | une confirmation humaine (*confirm*), une validation métier |

Une condition a souvent une **date** : `ARRETE-OK` du 27 n'est pas `ARRETE-OK` du 26. C'est ce qui évite qu'une chaîne se lance sur l'arrêté de la veille.

### 2.4 Ressources

- **Ressource quantitative** (sémaphore) : « au maximum N jobs en même temps » — ex. 1 seul job écrit dans la base comptable, 4 transferts simultanés maximum, protéger un serveur de la surcharge.
- **Ressource de contrôle** (exclusive ou partagée) : un job de sauvegarde demande la base en **exclusif** ; les jobs de lecture la demandent en **partagé**.

### 2.5 Calendriers

Jours ouvrés, **jours fériés**, calendrier **TARGET** (jours de fermeture du système de paiement européen : 1ᵉʳ janvier, Vendredi saint, lundi de Pâques, 1ᵉʳ mai, 25 et 26 décembre), dernier jour ouvré du mois, fin de trimestre, « J+1 ouvré »… Les calendriers sont **partagés** et maintenus une fois pour toutes les chaînes.

### 2.6 États d'un job et reprise

```
Planifié → En attente (de condition / fichier / ressource / heure) → En cours → OK
                                                                   └──→ En échec (NOT OK)
```

Actions d'exploitation classiques (et leur nom Control-M) :

| Action | Control-M | Usage |
|---|---|---|
| Mettre en attente | **Hold** / Free | empêcher un job de partir |
| Relancer | **Rerun** | relancer un job en échec (après correction) |
| Forcer l'état OK | **Set to OK** | le job est KO mais on décide de continuer (ex. traitement fait à la main) |
| Forcer le lancement | **Run Now** (bypass) | lancer sans attendre une condition |
| Tuer | **Kill** | arrêter un job en cours |
| Ordonnancer à la demande | **Order** / Force | ajouter au plan un job qui n'était pas prévu |
| Ajouter/retirer une condition | Add/Delete condition | débloquer une dépendance |
| Ignorer un jour | — | ne pas lancer la chaîne un jour donné |

**Idempotence** : un job qu'on peut relancer sans effet de bord (il nettoie avant d'écrire, ou écrit de façon atomique) simplifie énormément l'exploitation. C'est un **critère de qualité** des jobs batch.

### 2.7 SLA et prévision

On définit l'heure à laquelle la chaîne **doit** être terminée (ex. 6 h 30). L'ordonnanceur calcule le **chemin critique** et alerte dès qu'un retard compromet l'échéance — avant qu'il ne soit trop tard (Control-M : **SLA Management**, anciennement BIM).

---

## 3. Control-M en profondeur

### 3.1 Architecture

```
               ┌───────────────── Control-M/Enterprise Manager (EM) ─────────────────┐
  Web / client │  définitions (planification), moniteur, sécurité, audit, calendriers │
  Automation ─►│  serveur web + base de données + Automation API (REST)                │
  API (REST)   └──────────────┬──────────────────────────────────┬───────────────────┘
                              │                                  │
                   ┌──────────┴──────────┐            ┌──────────┴──────────┐
                   │ Control-M/Server    │            │ Control-M/Server    │   (un par datacenter, par
                   │ (« datacenter »)    │            │ (z/OS : Control-M   │    environnement…)
                   │ plan actif, New Day │            │  for z/OS)          │
                   └──────────┬──────────┘            └─────────────────────┘
                 ┌────────────┼─────────────┐
            ┌────┴───┐   ┌────┴───┐    ┌────┴───┐
            │ Agent  │   │ Agent  │    │ Agent  │  + Application Plug-ins / Integrations
            │ Linux  │   │Windows │    │  AIX   │    (SAP, bases de données, Hadoop, cloud, MFT,
            └────────┘   └────────┘    └────────┘     Informatica, Airflow, Kubernetes…)
```

| Composant | Rôle |
|---|---|
| **Control-M/EM** | point central : définitions, interface, utilisateurs et droits, calendriers globaux, audit |
| **Control-M/Server** | moteur d'ordonnancement d'un datacenter : il charge le **plan actif** et décide quand lancer chaque job |
| **Agent** | installé sur chaque serveur d'exécution, lance réellement les jobs et remonte les résultats et les logs (*sysout*) |
| **Plug-ins / Integrations** | types de jobs spécialisés (SAP, SQL, transfert de fichiers MFT, Kubernetes, AWS/Azure…) |
| **Automation API** | API REST + CLI `ctm` : tout faire « as code » |
| **Control-M SaaS / Helix** | version hébergée par BMC |

### 3.2 Les objets

| Objet | Description |
|---|---|
| **Folder** (dossier ; « table » dans les anciennes versions) | regroupe des jobs ; porte des règles de planification par défaut ; *SMART folder* : a ses propres règles et états |
| **Job** | type (Command, Script, FileWatcher, Database, FileTransfer, Kubernetes…), **Application**/**Sub-Application** (classement), **Host** (agent ou groupe d'hôtes), **RunAs** (utilisateur d'exécution) |
| **Scheduling** (`When`) | jours, mois, calendriers, heures (*From/To time*), cyclique (toutes les N minutes) |
| **Conditions** (*in/out*, `WaitForEvents` / `AddEvents` / `DeleteEvents`) | dépendances par événement **daté** (ODAT) ; un job « out » pose la condition, un job « in » l'attend |
| **Ressources** | *quantitative* (sémaphore : `Resource:Semaphore`) et *de contrôle* (`Resource:Mutex`, exclusive ou partagée) |
| **Variables** | `%%ODATE`, `%%JOBNAME`, `%%ORDERID`, variables utilisateur, variables globales (pools) |
| **Actions sur résultat** (*On/Do*, `If`) | si NOTOK → mail, relance, pose de condition, mise en échec d'un autre job… |
| **Rerun** | relance automatique (N fois, toutes les X minutes) |
| **Notifications / Shout** | messages vers une console, un mail, une alarme |
| **Calendars** | calendriers réguliers ou à règles (*Rule-Based Calendars*), partagés |
| **Host Group** | groupe d'agents pour répartir la charge / la haute disponibilité |

### 3.3 Le cycle de vie quotidien

1. **Définition** (*Planning domain*) : on crée/modifie les folders et jobs (UI, ou Jobs-as-Code), on les **déploie** (*deploy*).
2. **New Day** (à l'heure de bascule) : Control-M/Server calcule, pour la nouvelle date d'ordonnancement, quels jobs doivent tourner (selon leurs règles et calendriers) et les **ordonnance** dans le **plan actif** (*Active Jobs*, historiquement AJF : *Active Jobs File*). Les jobs non terminés de la veille peuvent rester (selon `Keep active`).
3. **Exécution** : chaque job attend ses prérequis (heure, conditions, ressources, confirmation), puis l'agent l'exécute.
4. **Monitoring** (*Monitoring domain*) : le pilote suit les états (couleurs : en attente, en cours, OK, NOT OK), consulte les *sysout* et le *log* du job, agit (Hold, Rerun, Set to OK, Kill…).
5. Historique, **audit**, rapports, archivage des sysout (*Workload Archiving*).

### 3.4 Jobs-as-Code et Automation API

Depuis plusieurs années, BMC pousse le **Jobs-as-Code** : les définitions sont écrites en **JSON** (ou en Python avec le SDK), versionnées dans Git, validées et déployées par une CI.

```json
{
  "Defaults": { "Application": "BANQUE", "SubApplication": "ARRETE", "RunAs": "batch", "Host": "agent-batch-01" },
  "ARRETE_COMPTABLE": {
    "Type": "Folder",
    "When": { "WeekDays": ["MON", "TUE", "WED", "THU", "FRI"], "FromTime": "2200" },
    "ATTENDRE_FICHIER": {
      "Type": "Job:FileWatcher:Create",
      "Path": "/data/in/transactions_%%ODATE.csv",
      "SearchInterval": "60",
      "TimeLimit": "120"
    },
    "CONTROLER_FICHIER": {
      "Type": "Job:Command",
      "Command": "/opt/batch/scripts/controler_fichier.sh %%ODATE"
    },
    "CHAINE": { "Type": "Flow", "Sequence": ["ATTENDRE_FICHIER", "CONTROLER_FICHIER"] }
  }
}
```

Le CLI `ctm` (Node.js) :

```bash
ctm environment add <nom> <url-automation-api> <user> <password>   # ou ctm environment workbench::add
ctm environment set <nom>
ctm session login
ctm build ARRETE_COMPTABLE.json          # valide la syntaxe et la cohérence (sans déployer)
ctm run   ARRETE_COMPTABLE.json          # déploie temporairement et exécute (tests)
ctm deploy ARRETE_COMPTABLE.json         # déploie les définitions dans l'EM
ctm run order <server> ARRETE_COMPTABLE  # ordonnance le folder
ctm run status <runId>                   # suit l'exécution
ctm run job:output::get <jobId>          # sysout
ctm run job::rerun <jobId>  /  job::setToOk  /  job::hold  /  job::kill
ctm deploy jobs::get -s "folder=ARRETE*" # exporte les définitions existantes en JSON
```

Pipeline typique « jobs as code » en banque : PR sur le repo des définitions → CI qui exécute `ctm build` (validation) → déploiement en recette avec `ctm deploy` → tests → déploiement en production via la chaîne de MEP (souvent XL Release, module 16). Un **Deploy Descriptor** adapte les valeurs par environnement (hôtes, utilisateurs, chemins) — l'équivalent des overlays Kustomize.

**Control-M Workbench** : conteneur gratuit (EM + Server + Agent dans une seule image, ~8 Go de RAM) pour développer et tester des définitions en local. Non persistant : les définitions vivent dans Git.

### 3.5 Bonnes pratiques Control-M

- Conventions de nommage strictes (application, environnement, fonction) : `BQ_ARR_CTRL_FIC`…
- Un job = une fonction ; codes retour significatifs (0 OK, ≠ 0 KO) et logs explicites dans la sysout.
- Jobs **idempotents** et **reprenables**.
- Conditions nommées clairement, toujours supprimées en fin de cycle si nécessaire (sinon déclenchements fantômes).
- Ressources pour protéger les systèmes partagés.
- Calendriers centralisés, jamais de dates en dur.
- Consignes de pilotage associées à chaque job (champ *Description* / documentation).
- Définitions en Git (Jobs-as-Code), revues et déployées par pipeline.

---

## 4. Les autres ordonnanceurs du marché (pour t'y retrouver)

| Concept | Control-M | Dollar Universe ($U) | VTOM | Autosys | Airflow |
|---|---|---|---|---|---|
| Chaîne | Folder | Session | Application | Box | DAG |
| Job | Job | Uproc | Job (Traitement) | Job | Task |
| Date métier | ODATE | date de traitement | date d'exploitation | — | logical date |
| Dépendance inter-chaînes | Conditions | conditions / ressources | liens / ressources | conditions (success(), file()) | Assets / ExternalTaskSensor |
| Limiter la concurrence | Resource (quantitative) | ressources | ressources | resources / virtual machine | Pools |
| Attente fichier | File Watcher | ressource fichier | ressource fichier | file watcher job | FileSensor |
| Calendrier | Calendar / RBC | calendrier | calendrier | calendar | cron + timetable / logique de saut |
| Relance | Rerun | relance | relance | force start | Clear |
| Forcer OK | Set to OK | mise à jour statut | — | change status | Mark success |
| Définitions as code | JSON + `ctm` | export XML / API | export / API | JIL | Python |

---

## 5. Apache Airflow (notre terrain de pratique)

Né chez Airbnb, projet Apache, très utilisé pour les pipelines de données et de plus en plus pour l'orchestration générale. Version 3 depuis 2025.

### Architecture (version 3)

```
 api-server (UI + API REST)   scheduler (décide quoi lancer)   dag-processor (lit les fichiers Python)
            \                          |                                 /
             └──────────────── base de métadonnées (PostgreSQL) ────────┘
                                       │
                          executor (Celery + Redis ici) → workers (exécutent les tâches)
                          triggerer (attentes asynchrones)
```

### Concepts

| Concept | Description |
|---|---|
| **DAG** | graphe orienté acyclique de tâches, écrit en **Python** (la définition EST du code) |
| **Task / Operator** | `BashOperator`, `PythonOperator`, `EmptyOperator`, opérateurs fournis par des *providers* (SQL, Kubernetes, cloud…) |
| **Sensor** | tâche qui attend une condition (`FileSensor`, `ExternalTaskSensor`…) ; mode `reschedule` pour libérer le worker pendant l'attente |
| **DAG Run** | une exécution du DAG, pour une **logical date** (= ODATE) |
| **Task Instance** | une exécution d'une tâche dans un DAG run, avec son état (queued, running, success, failed, up_for_retry, skipped…) |
| **schedule** | expression cron, intervalle, *timetable* personnalisé, ou **Asset** (déclenchement par un événement de données) |
| **Pool** | nombre de slots partagés entre tâches (= ressource quantitative) |
| **Retries** | relances automatiques avec délai |
| **Trigger rules** | `all_success` (défaut), `one_failed`, `all_done`, `none_failed`… |
| **ShortCircuitOperator** | arrête la suite si une condition est fausse (ex. jour férié) |
| **Connections / Variables** | paramètres externes (connexion à un système, chemins) |
| **Templates Jinja** | `{{ ds }}`, `{{ ds_nodash }}`, `{{ logical_date }}` : la date métier injectée dans les commandes |
| **Backfill / Clear** | rejouer des dates passées / relancer des tâches |

### Limites d'Airflow face à un ordonnanceur de production bancaire

Pas de vrai « plan de production » journalier visible d'un coup d'œil, pas de gestion native des calendriers bancaires (on code la logique), SLA moins riches (remplacés par les *deadline alerts* en v3), exécution centrée sur ses propres workers (pas d'agents natifs sur AIX ou mainframe), interface pensée pour la donnée plus que pour le pilotage de nuit. C'est pour ça que les banques gardent Control-M… et que Control-M sait **piloter des DAGs Airflow** comme des jobs.

---

## 6. Correspondance pour les labs

| Ce que tu fais dans Airflow (lab) | Équivalent Control-M |
|---|---|
| `schedule="0 22 * * 1-5"` + `ShortCircuitOperator` jours TARGET | `When` WeekDays + calendrier TARGET |
| `{{ ds_nodash }}` | `%%ODATE` |
| `FileSensor` en mode reschedule | `Job:FileWatcher:Create` |
| `retries=2, retry_delay=2 min` | `Rerun: Times 2, Every 2 Minutes` |
| `pool="db_batch"` (1 slot) | `Resource:Semaphore` quantité 1 |
| `outlets=[Asset(...)]` / `schedule=[Asset(...)]` | `AddEvents` / `WaitForEvents` (condition `ARRETE-OK`) |
| *Clear* d'une tâche | **Rerun** |
| *Mark as success* | **Set to OK** |
| `on_failure_callback` | `If CompletionStatus NOTOK → Mail` |
| Pause du DAG | **Hold** du folder |

---

## Pièges classiques

- Confondre **date d'exécution** et **date métier** : relancer « le job d'hier » doit traiter les données d'hier.
- Capteur de fichier qui démarre le traitement sur un fichier **en cours d'écriture** → le partenaire doit écrire sous un nom temporaire puis renommer (écriture atomique), ou déposer un **fichier témoin** (`.ok`, `.done`) après le fichier de données.
- Jobs non idempotents → une relance double les écritures.
- Conditions jamais nettoyées → chaînes déclenchées par des conditions périmées.
- Absence de ressource sur une base partagée → verrous, *deadlocks*, lenteurs de nuit.
- Calendriers codés « en dur » dans chaque chaîne → oublis lors des jours fériés.
- `Set to OK` sans trace écrite → l'audit ne comprend plus pourquoi la chaîne a continué.

---

## Pour aller plus loin

- [Control-M Automation API — documentation et exemples](https://controlm.github.io/) · [Control-M Workbench (GitHub)](https://github.com/controlm/workbench) · [Automation API community solutions](https://github.com/controlm/automation-api-community-solutions)
- [Apache Airflow — documentation](https://airflow.apache.org/docs/) · [Running Airflow in Docker](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [JS7 JobScheduler](https://www.sos-berlin.com/en/js7) — ordonnanceur open source « à la Control-M » (agents, plan journalier, ressources), alternative à explorer
