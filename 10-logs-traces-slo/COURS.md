# Module 10 — Observabilité (2/2) : logs, traces, SLO et gestion d'incident

> **Objectif** : centraliser et interroger les logs (Loki + Alloy, LogQL), tracer les requêtes de bout en bout (OpenTelemetry + Tempo), **corréler** métriques, logs et traces, puis piloter la fiabilité avec des **SLI/SLO/budgets d'erreur** et des alertes de *burn rate*, jusqu'au postmortem.
>
> **Durée** : cours ~2 h · labs ~3 h · quiz 30 min

---

## 1. Les logs dans Kubernetes

### Le chemin d'un log

```
app ──stdout/stderr──► runtime (containerd) ──► /var/log/pods/<ns>_<pod>_<uid>/<conteneur>/0.log  (sur le nœud)
                                                     │  (rotation par le kubelet : 10 Mo × 5 par défaut)
                                                     ▼
                         agent de collecte (DaemonSet) : Alloy, Fluent Bit, Vector, OTel Collector
                                                     │  enrichit (namespace, pod, labels), parse, filtre
                                                     ▼
                         stockage + requêtes : Loki, Elasticsearch/OpenSearch, Splunk, Datadog, CloudWatch…
```

- L'application écrit sur **stdout**, jamais dans un fichier (12-factor) : la plateforme se charge du reste.
- `kubectl logs` lit les fichiers du nœud : quand le pod est supprimé ou le nœud perdu, **les logs disparaissent**. D'où la centralisation.
- **Logs structurés (JSON)** : chaque champ devient filtrable (`level`, `route`, `status`, `duration_ms`, `trace_id`). Un log texte libre impose des regex fragiles.
- Niveaux : `DEBUG` (dev), `INFO`, `WARNING`, `ERROR`. En prod on évite DEBUG (volume, coût, données sensibles).
- **Jamais de secrets ni de données personnelles** dans les logs (mots de passe, tokens, cartes, parfois e-mails/IP selon le RGPD).

### Agents : le paysage en 2026

| Agent | Remarque |
|---|---|
| **Grafana Alloy** | successeur de **Promtail** (fin de vie début 2026) et du Grafana Agent ; distribution de l'OpenTelemetry Collector ; logs + métriques + traces + profils ; config en langage « Alloy » (ex-River) |
| Fluent Bit | léger (C), très répandu, nombreux plugins de sortie |
| Vector | Rust, performant, transformations puissantes (VRL) |
| OpenTelemetry Collector | standard vendor-neutral pour les 3 signaux |

---

## 2. Loki

### Le principe : n'indexer que les labels

Elasticsearch indexe **le contenu** de chaque log (puissant, mais stockage et RAM coûteux). Loki n'indexe que des **labels** (comme Prometheus) et stocke le contenu compressé en **chunks** sur un stockage objet bon marché. On sélectionne d'abord un **flux** par ses labels, puis on filtre le texte « à la volée ».

```
{namespace="taskapi-prod", app="taskapi", level="error"}   ← flux (stream) : index
   2026-10-24T14:02:11Z {"level":"error","msg":"…","trace_id":"4bf9…"}   ← contenu : chunks
```

> ⚠ Même règle que Prometheus : **peu de labels, à faible cardinalité** (namespace, app, container, level). Jamais d'ID utilisateur, de trace_id ou d'URL en label → trop de flux, Loki s'effondre. Ces valeurs restent dans le contenu (ou en *structured metadata*).

### Architecture

Composants : distributor → ingester (écrit les chunks) → stockage objet ; querier / query-frontend pour lire ; compactor (rétention). Modes de déploiement : **monolithique** (un binaire : notre cas), *simple scalable* (read/write/backend), **microservices** (grandes volumétries). Les charts Helm de Loki et Tempo sont désormais publiés par **grafana-community** (migration début 2026).

### LogQL

```logql
{namespace="taskapi-dev", app="taskapi"}                          # sélection du flux (obligatoire)
{app="taskapi"} |= "erreur"                                       # contient   (!= ne contient pas, |~ regex)
{app="taskapi"} | json                                            # parse le JSON → champs utilisables
{app="taskapi"} | json | status >= 500 | line_format "{{.method}} {{.path}} {{.status}} {{.duration_ms}}ms"
{app="taskapi"} | json | duration_ms > 300                        # requêtes lentes
{app="taskapi"} | logfmt / | pattern "<ip> - <_> [<ts>] \"<method> <path> …\""

# Requêtes MÉTRIQUES à partir des logs (comme PromQL) :
sum by (namespace) (rate({app="taskapi"} | json | status >= 500 [5m]))
sum by (route) (count_over_time({app="taskapi"} | json [1h]))
quantile_over_time(0.95, {app="taskapi"} | json | unwrap duration_ms [5m]) by (namespace)
```

Grafana permet aussi de créer des alertes à partir de LogQL (*Loki ruler*).

---

## 3. Traces distribuées

### Pourquoi

Une requête utilisateur traverse plusieurs services (gateway → API → base → file → autre service…). Quand elle est lente, **où** est passé le temps ? Les métriques disent « le p95 a doublé », les logs disent « cette requête a mis 2 s », la **trace** montre la décomposition :

```
trace_id 4bf92f3577b34da6a3ce929d0e0e4736                         durée totale 1 240 ms
└─ GET /api/tasks (taskapi)                         ████████████████████████████  1 240 ms
   ├─ middleware chaos (latence injectée)           ██████████████████            800 ms
   └─ SELECT tasks (postgresql)                                       ████        210 ms
```

### Vocabulaire

| Terme | Sens |
|---|---|
| **Trace** | l'arbre complet d'une requête, identifié par un `trace_id` (128 bits) |
| **Span** | une opération (appel HTTP, requête SQL, fonction) : nom, début, durée, statut, **attributs**, événements ; a un `span_id` et un parent |
| **Propagation de contexte** | le `trace_id` voyage entre services dans un en-tête HTTP standard **W3C `traceparent`** |
| **Échantillonnage** | *head sampling* (décidé au début : ex. 10 % des traces) ou *tail sampling* (décidé à la fin : garder toutes les traces en erreur ou lentes) |
| **Conventions sémantiques** | noms d'attributs standard : `http.request.method`, `http.route`, `db.system`, `service.name`… |

### OpenTelemetry (OTel)

Le **standard CNCF** pour produire de la télémétrie, indépendant des fournisseurs :

```
Application ─(API + SDK OTel, instrumentation auto ou manuelle)─► OTLP ─► Collector (Alloy) ─► Tempo / Jaeger / Datadog / …
```

- **API** (ce que le code appelle) / **SDK** (implémentation : échantillonnage, export) / **instrumentations** (FastAPI, SQLAlchemy, requests, Spring… sans toucher au code métier) / **OTLP** (protocole, gRPC 4317 ou HTTP 4318) / **Collector** (réception, traitement par lots, filtrage, routage, export).
- Dans taskapi : `telemetry.py` active `FastAPIInstrumentor` et `SQLAlchemyInstrumentor`, le `service.name`, et l'exporteur OTLP HTTP — seulement si `OTEL_ENABLED=true`.
- **Changer de backend = changer la config du collecteur**, pas le code. C'est tout l'intérêt.

### Tempo

Backend de traces de Grafana : stocke les traces **sans index** sur du stockage objet (pas cher), retrouvées par `trace_id` ou via **TraceQL** :

```traceql
{ resource.service.name = "taskapi" && duration > 500ms }
{ span.http.response.status_code >= 500 }
{ resource.service.name = "taskapi" } >> { span.db.system = "postgresql" && duration > 100ms }
```

Alternatives : Jaeger (CNCF), Zipkin, et les SaaS (Datadog APM, Honeycomb, New Relic…).

---

## 4. Corréler les trois signaux

| Depuis | Vers | Mécanisme |
|---|---|---|
| Log | Trace | `trace_id` écrit dans chaque log (taskapi le fait dans `logging_setup.py`) + *derived field* sur la datasource Loki |
| Trace | Logs | *traces to logs* sur la datasource Tempo : requête Loki filtrée par `trace_id` et `service.name` |
| Métrique | Trace | **exemplars** : un `trace_id` attaché à un point d'histogramme (format OpenMetrics) |
| Trace | Métriques | *metrics generator* de Tempo : métriques RED et graphe de services calculés à partir des spans |

Workflow d'investigation type : **alerte** (métrique) → **dashboard** (quand ? quelle route ? quel env ?) → **logs** de la période filtrés sur les erreurs → **trace** d'une requête fautive → cause.

---

## 5. SLI, SLO, SLA et budget d'erreur

| Terme | Définition | Exemple |
|---|---|---|
| **SLI** (indicator) | mesure de la qualité de service **vue par l'utilisateur**, idéalement un ratio « bons événements / événements valides » | % de requêtes `/api/*` sans erreur 5xx ; % répondues en < 250 ms |
| **SLO** (objective) | cible interne sur un SLI, sur une fenêtre | 99 % sur 30 jours glissants |
| **SLA** (agreement) | engagement **contractuel** avec pénalités | 99,5 % sinon avoir de 10 % — toujours moins strict que le SLO |
| **Budget d'erreur** | 1 − SLO : ce qu'on a le **droit** de rater | 1 % des requêtes ≈ 7 h 18 d'indisponibilité totale par mois |

| SLO | Indisponibilité autorisée / 30 j |
|---|---|
| 99 % | 7 h 18 min |
| 99,5 % | 3 h 39 min |
| 99,9 % | 43 min |
| 99,99 % | 4 min 23 s |

### Pourquoi c'est puissant

- Le SLO **aligne dev et ops** : tant qu'il reste du budget, on livre vite (on peut prendre des risques) ; budget épuisé → **gel des fonctionnalités**, priorité à la fiabilité. C'est une décision objective, pas un débat.
- 100 % n'est **jamais** le bon objectif (coût infini, et l'utilisateur ne le perçoit pas à cause de son propre réseau).
- Choisir peu de SLO, centrés sur les parcours utilisateurs critiques.

### Alerter sur le *burn rate*

Le **burn rate** = vitesse de consommation du budget. Burn rate 1 → budget épuisé exactement en fin de fenêtre (30 j). Burn rate 14,4 → épuisé en ~2 jours.

Approche **multi-window, multi-burn-rate** (Google SRE Workbook) :

| Sévérité | Burn rate | Fenêtre longue | Fenêtre courte (confirmation) | Budget consommé à l'alerte |
|---|---|---|---|---|
| page (urgent) | 14,4 | 1 h | 5 min | 2 % |
| page | 6 | 6 h | 30 min | 5 % |
| ticket | 1 | 3 j | 6 h | 10 % |

La **fenêtre longue** évite les faux positifs (un pic de 30 s ne réveille personne), la **fenêtre courte** permet à l'alerte de **se résoudre vite** une fois le problème corrigé. C'est bien supérieur à « taux d'erreur > 5 % pendant 2 min ». Outils pour générer ces règles : **Sloth**, **Pyrra**, OpenSLO.

---

## 6. Gestion d'incident

### Pendant

1. **Détecter** (alerte, idéalement avant les utilisateurs) → **MTTD**.
2. **Déclarer** l'incident, nommer un *Incident Commander*, ouvrir un canal dédié, communiquer (page de statut).
3. **Mitiger d'abord, comprendre ensuite** : rollback, feature flag, scale, bascule. Restaurer le service est la priorité → **MTTR**.
4. Tenir une **chronologie** au fil de l'eau.

### Après : le postmortem *blameless*

Document factuel (modèle : [POSTMORTEM-TEMPLATE.md](POSTMORTEM-TEMPLATE.md)) : impact, chronologie, cause racine et facteurs contributifs (« 5 pourquoi »), ce qui a bien/mal marché, **actions correctives suivies**. « Sans reproche » : on corrige le système (tests, alertes, garde-fous, automatisation) plutôt que de blâmer une personne — sinon les gens cachent les erreurs et on n'apprend rien.

### DORA, encore

*Change failure rate* et *temps de restauration* sont deux des 4 métriques DORA : GitOps (rollback = revert), les déploiements progressifs et de bonnes alertes SLO les améliorent directement.

---

## Pièges classiques

- Labels Loki à forte cardinalité (trace_id, user_id, pod éphémère dans des jobs massifs…) → explosion du nombre de flux.
- Logs non structurés → requêtes regex lentes et fragiles.
- Traces sans propagation de contexte entre services → traces en morceaux.
- Échantillonnage head à 1 % → la trace de l'erreur rare n'existe pas (tail sampling).
- SLO définis sur des métriques d'infrastructure (CPU) au lieu de l'expérience utilisateur.
- SLA plus strict que le SLO interne.
- Alertes sur chaque symptôme ET sur le SLO → doublons ; à terme, les alertes SLO remplacent beaucoup d'alertes de seuil.
- Postmortem qui cherche un coupable, ou sans actions suivies.

---

## Pour aller plus loin

- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) (chapitre de référence)
- [OpenTelemetry — documentation](https://opentelemetry.io/docs/) · [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [LogQL](https://grafana.com/docs/loki/latest/query/) · [TraceQL](https://grafana.com/docs/tempo/latest/traceql/)
- [Sloth](https://sloth.dev/) — générateur de règles SLO
- [PagerDuty Incident Response guide](https://response.pagerduty.com/)
