# Module 09 — Observabilité (1/2) : métriques, Prometheus, alerting, Grafana

> **Objectif** : comprendre le modèle de Prometheus (pull, séries temporelles, labels), écrire du **PromQL** avec aisance, instrumenter et collecter une application (ServiceMonitor), concevoir des **alertes utiles** (règles, Alertmanager, runbooks) et des **dashboards as code** dans Grafana.
>
> **Durée** : cours ~2 h · labs ~3 h · quiz 30 min

---

## 1. Monitoring vs observabilité

- **Monitoring** : surveiller des indicateurs **connus à l'avance** et alerter quand ils dérivent (« le CPU dépasse 90 % »). Répond aux *known unknowns*.
- **Observabilité** : capacité à comprendre l'état interne d'un système **à partir de ce qu'il émet**, y compris pour des problèmes jamais vus (*unknown unknowns*) : « pourquoi les requêtes des clients de cette région sont lentes depuis 14 h 02 ? ».

Les **signaux** :

| Signal | Question | Outil (ici) |
|---|---|---|
| **Métriques** | combien ? à quelle vitesse ? (agrégé, pas cher, idéal pour alerter) | Prometheus |
| **Logs** | que s'est-il passé exactement ? (événement détaillé) | Loki (module 10) |
| **Traces** | où le temps a-t-il été passé dans une requête distribuée ? | Tempo + OpenTelemetry (module 10) |
| Profils (4ᵉ signal) | quelle fonction consomme le CPU/la mémoire ? | Pyroscope |

La valeur vient de la **corrélation** : une alerte (métrique) → le dashboard → les logs de la période → la trace d'une requête lente.

### Que mesurer ? Les méthodes

| Méthode | Pour | Indicateurs |
|---|---|---|
| **RED** | les **services** (requêtes) | **R**ate (débit), **E**rrors (taux d'erreur), **D**uration (latence, en percentiles) |
| **USE** | les **ressources** (CPU, disque, réseau, pool de connexions) | **U**tilization, **S**aturation (file d'attente), **E**rrors |
| **4 Golden Signals** (Google SRE) | tout service exposé | latence, trafic, erreurs, saturation |

---

## 2. Prometheus : architecture

```
                    ┌───────────────────────── Prometheus ─────────────────────────┐
 Service discovery ►│ découverte des cibles (Kubernetes, fichiers, Consul, cloud…)  │
 (API Kubernetes)   │ relabeling → liste de cibles                                  │
                    │ SCRAPE (pull HTTP GET /metrics toutes les 15-30 s)  ─────────►│──► cibles : apps, exporters
                    │ TSDB locale (blocs de 2 h, compaction, rétention)             │
                    │ moteur de règles : recording rules + alerting rules ─────────►│──► Alertmanager ──► Slack, mail, PagerDuty…
                    │ API HTTP / PromQL ◄── Grafana                                  │
                    └──────────────────────┬───────────────────────────────────────┘
                                           └─ remote_write ──► Thanos / Mimir / Cortex / VictoriaMetrics (long terme, HA, global)
```

- **Pull** : Prometheus va chercher les métriques. Avantages : il sait si une cible est **down** (`up == 0`), pas de surcharge en cas de pic, configuration centralisée. Pour les jobs batch éphémères : **Pushgateway** (avec parcimonie).
- **Exporters** : traduisent les métriques d'un système tiers au format Prometheus : `node-exporter` (machine), `kube-state-metrics` (état des objets K8s), `cAdvisor` (conteneurs, intégré au kubelet), `postgres-exporter`, `blackbox-exporter` (sondes HTTP/TCP externes)…
- **Un seul nœud, stockage local** : Prometheus n'est pas fait pour la rétention longue ni la HA ; on ajoute Thanos/Mimir pour ça.

### Prometheus Operator et kube-prometheus-stack

Dans Kubernetes on ne configure pas `prometheus.yml` à la main : le **Prometheus Operator** génère la configuration à partir de CRD :

| CRD | Rôle |
|---|---|
| `Prometheus`, `Alertmanager` | les instances déployées |
| **`ServiceMonitor`** | « scrape les endpoints des Services qui ont ces labels, sur ce port nommé » |
| `PodMonitor` | idem, directement sur des pods |
| **`PrometheusRule`** | règles d'enregistrement et d'alerte |
| `AlertmanagerConfig` | routage d'alertes par namespace |
| `Probe` | sondes blackbox |

**kube-prometheus-stack** (chart Helm) installe tout : operator, Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, + des **centaines de règles et dizaines de dashboards** prêts à l'emploi (Kubernetes Mixins).

---

## 3. Le modèle de données

```
http_requests_total{job="taskapi", namespace="taskapi-prod", route="/api/tasks", method="GET", status="200"}  1543  @1729000000
└───── nom ───────┘└──────────────────────────────── labels ─────────────────────────────────────────┘ valeur  horodatage
```

Une **série temporelle** = un nom + un ensemble unique de labels. Chaque combinaison distincte de labels **crée une nouvelle série**.

> ⚠ **Cardinalité** : mettre un identifiant utilisateur, une URL brute (`/api/tasks/42`), un ID de requête ou un timestamp dans un label crée des millions de séries → mémoire explosée, Prometheus qui tombe. C'est pour ça que taskapi utilise le **template de route** (`/api/tasks/{task_id}`) et regroupe les 404 sous `route="unmatched"`. Règle : labels à **valeurs bornées** uniquement.

### Les 4 types de métriques

| Type | Comportement | Exemple | On l'exploite avec |
|---|---|---|---|
| **Counter** | ne fait que monter (remis à 0 au redémarrage) | `http_requests_total` | `rate()`, `increase()` — jamais la valeur brute |
| **Gauge** | monte et descend | `http_requests_in_progress`, mémoire | valeur directe, `avg_over_time()`, `deriv()` |
| **Histogram** | compte les observations par **buckets** cumulés (`_bucket{le="0.5"}`), + `_sum` et `_count` | `http_request_duration_seconds` | `histogram_quantile()` — agrégeable entre instances ✅ |
| **Summary** | quantiles calculés côté client | | non agrégeable entre instances ❌ (préférer l'histogramme) |

Conventions de nommage : unité de base SI dans le nom (`_seconds`, `_bytes`), `_total` pour les counters, `snake_case`.

---

## 4. PromQL

### Sélecteurs

```promql
http_requests_total                                     # vecteur instantané : dernière valeur de chaque série
http_requests_total{namespace="taskapi-prod", status=~"5.."}   # =, !=, =~ (regex), !~
http_requests_total[5m]                                 # vecteur de plage : toutes les valeurs des 5 dernières minutes
http_requests_total offset 1h                           # il y a une heure
```

### Fonctions essentielles

```promql
rate(http_requests_total[5m])              # débit moyen par seconde sur 5 min (gère les remises à zéro) ✅ alertes/graphes
irate(http_requests_total[5m])             # débit instantané (2 derniers points) : graphes très réactifs, bruités
increase(http_requests_total[1h])          # nombre d'événements sur 1 h (= rate × durée)
```

Règle : la fenêtre de `rate()` doit couvrir **au moins 4 intervalles de scrape** (scrape 30 s → `[2m]` minimum, `[5m]` confortable).

### Agrégation

```promql
sum by (namespace, route) (rate(http_requests_total[5m]))       # garde ces labels
sum without (pod, instance) (rate(http_requests_total[5m]))     # retire ces labels
avg, min, max, count, topk(5, …), bottomk, quantile, count_values
```

⚠ **Toujours `rate()` PUIS `sum()`**, jamais l'inverse (`sum` de counters de pods qui redémarrent fausse tout).

### Ratios et percentiles

```promql
# Taux d'erreur
  sum(rate(http_requests_total{status=~"5.."}[5m]))
/ sum(rate(http_requests_total[5m]))

# Latence p95 (agréger les buckets en gardant "le" !)
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))

# Latence moyenne
  rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])
```

### Opérateurs et utilitaires

```promql
up == 0                                     # filtre : séries dont la valeur est 0
absent(up{job="taskapi"})                   # 1 si la série n'existe pas du tout (cible disparue)
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0   # disque plein dans 24 h ?
rate(a[5m]) > on (namespace) group_left … # jointures entre séries (on, ignoring, group_left/right)
avg_over_time(x[1h]), max_over_time, quantile_over_time
```

### Recording rules

Pré-calculer des requêtes coûteuses ou très utilisées, sous un nom normalisé `niveau:métrique:opérations` :

```yaml
- record: namespace:taskapi_http_errors:ratio_rate5m
  expr: sum by (namespace) (rate(http_requests_total{status=~"5.."}[5m])) / sum by (namespace) (rate(http_requests_total[5m]))
```

Dashboards et alertes deviennent plus rapides et plus lisibles.

---

## 5. Alerting

### Règles d'alerte

```yaml
- alert: TaskapiHighErrorRate
  expr: namespace:taskapi_http_errors:ratio_rate5m > 0.05
  for: 2m                      # doit rester vraie 2 min (évite les faux positifs sur un pic)
  labels:
    severity: critical         # utilisé pour le routage
  annotations:
    summary: "{{ $value | humanizePercentage }} d'erreurs ({{ $labels.namespace }})"
    runbook_url: https://…     # QUOI FAIRE
```

États : **inactive** → **pending** (condition vraie, `for` pas encore écoulé) → **firing** → résolue.

### Alertmanager

```
alertes ──► déduplication ──► GROUPEMENT (group_by, group_wait, group_interval) ──► ROUTAGE (arbre de routes, matchers)
                                                       │                                     │
                                          INHIBITION (critique masque warning)     RÉCEPTEURS (Slack, PagerDuty, mail, webhook…)
                                          SILENCES (maintenance planifiée)         repeat_interval (rappels)
```

- **Grouper** : 50 pods en erreur = 1 notification, pas 50.
- **Router** : `severity=critical` → pager d'astreinte ; `warning` → canal Slack ; `team=data` → leur canal.
- **Inhiber** : si `ClusterDown`, ne pas envoyer les 300 alertes qui en découlent.
- **Silences** : pendant une maintenance (`amtool silence add …` ou l'UI).
- Le **Watchdog** (alerte toujours active) prouve que la chaîne d'alerting fonctionne : si on ne la reçoit plus (*dead man's switch*), c'est l'alerting qui est cassé.

### Une bonne alerte

| ✅ | ❌ |
|---|---|
| alerte sur un **symptôme** visible par l'utilisateur (erreurs, latence, indisponibilité) | alerte sur une cause hypothétique (« CPU à 80 % ») qui n'a pas d'impact |
| **actionnable** : quelqu'un doit faire quelque chose, maintenant | « pour info » → c'est un dashboard ou un ticket, pas une alerte |
| a un **runbook** | oblige à tout redécouvrir à 3 h du matin |
| peu fréquente, rarement fausse | **fatigue d'alerte** → les vraies sont ignorées |
| sévérité qui reflète l'urgence (page vs ticket) | tout en critical |

Le module 10 va plus loin avec les alertes basées sur les **SLO** (burn rate).

---

## 6. Grafana

- **Datasources** : Prometheus, Loki, Tempo, mais aussi PostgreSQL, Elasticsearch, CloudWatch, Azure Monitor…
- **Dashboards** : panels (time series, stat, gauge, bar, table, heatmap pour les histogrammes, logs, traces, node graph), **variables** (`$namespace`, `$datasource`) pour un dashboard réutilisable, *repeat* de panels, annotations (déploiements !), liens entre dashboards.
- **Explore** : requêtes ad hoc, idéal en investigation, *split view* métriques/logs.
- **Dashboards as code** : JSON versionné et **provisionné** (ici : ConfigMap labellisée `grafana_dashboard: "1"`, détectée par le *sidecar* de Grafana). Pour aller plus loin : Grafonnet (Jsonnet), Grafana Foundation SDK, provider Terraform `grafana`, Grizzly. Un dashboard modifié à la main dans l'UI est **perdu** au prochain redéploiement — c'est voulu.
- **Grafana Alerting** existe aussi (alertes définies dans Grafana, multi-sources) ; avec Prometheus Operator on reste souvent sur PrometheusRule + Alertmanager (alertes versionnées avec le reste).

Bonnes pratiques de dashboard : une question par dashboard (« le service va-t-il bien ? »), RED en haut, ressources en dessous, percentiles plutôt que moyennes, unités renseignées, seuils colorés, pas de mur de 40 graphes.

---

## 7. Instrumenter une application

Dans taskapi (`app/src/taskapi/metrics.py`) avec la librairie officielle `prometheus_client` :

```python
HTTP_REQUESTS = Counter("http_requests_total", "…", ["method", "route", "status"])
HTTP_LATENCY = Histogram("http_request_duration_seconds", "…", ["method", "route"],
                         buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5))
```

- Choisir les **buckets** autour de tes objectifs (ici le seuil de 500 ms et 300 ms tombent sur des bornes : le p95 est précis là où ça compte).
- Exposer `/metrics`, puis le déclarer avec un **ServiceMonitor** (port **nommé** du Service).
- Les métriques **métier** comptent autant que les techniques (`taskapi_tasks_created_total`).
- `taskapi_build_info{version, env} 1` : permet de joindre la version déployée aux autres métriques et de voir les déploiements sur les graphes.
- OpenTelemetry Metrics est l'alternative standardisée (export OTLP, conversion vers Prometheus).

---

## Pièges classiques

- ServiceMonitor ignoré : labels ne correspondant pas au sélecteur de Prometheus (d'où `serviceMonitorSelectorNilUsesHelmValues: false`), port non nommé, NetworkPolicy qui bloque le namespace `monitoring`.
- `rate()` sur une jauge, `sum()` avant `rate()`, fenêtre de `rate` trop courte.
- `histogram_quantile` sans garder `le` dans l'agrégation → résultat absurde.
- Moyennes de latence qui cachent les pires cas → percentiles.
- Cardinalité non maîtrisée.
- kind/Docker : etcd, scheduler, controller-manager, kube-proxy injoignables → alertes « Down » permanentes si on ne les désactive pas ; node-exporter qui échoue à monter `/` sous WSL.
- Alertes sans `for` (bruyantes) ou avec un `for` trop long (on rate l'incident).

---

## Pour aller plus loin

- [Prometheus — Querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) · [PromLabs PromQL cheat sheet](https://promlabs.com/promql-cheat-sheet/)
- [Awesome Prometheus alerts](https://samber.github.io/awesome-prometheus-alerts/) — bibliothèque de règles
- [Google SRE book — Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Grafana — dashboard best practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
