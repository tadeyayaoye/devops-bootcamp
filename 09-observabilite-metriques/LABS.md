# Module 09 — Labs métriques, alerting, Grafana

> ⏱ ~3 h · Tout se déploie **par GitOps** : tu écris dans `~/devops-bootcamp-gitops`, tu pousses, Argo CD applique.
> RAM : arrête SonarQube (`make sonar-down`) — le pipeline continue sans analyse (build « unstable »).

---

## Lab 9.1 — Déployer kube-prometheus-stack par GitOps (≈ 35 min)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm search repo prometheus-community/kube-prometheus-stack | head -2
helm show values prometheus-community/kube-prometheus-stack > /tmp/kps-defaults.yaml && wc -l /tmp/kps-defaults.yaml
```

Dans le repo GitOps :

1. `platform/values/kube-prometheus-stack.yaml` : `fullnameOverride: kps` ; désactiver etcd / controller-manager / scheduler / kube-proxy (et leurs règles) ; `prometheus-node-exporter.hostRootFsMount.enabled: false` ; Prometheus (rétention 2 j, sélecteurs `*NilUsesHelmValues: false`, ressources) ; Grafana (`adminPassword`, sidecar dashboards) ; Alertmanager avec un récepteur **webhook** `http://alert-sink.monitoring.svc:8080/` et les routes `null` pour Watchdog/InfoInhibitor.
2. `argocd/20-monitoring.yaml` : Application **multi-sources** (chart + `$values/platform/values/…`), projet `platform`, namespace `monitoring`, `ServerSideApply=true`, **version épinglée**.

```bash
git add . && git commit -m "feat(monitoring): kube-prometheus-stack" && git push
argocd app wait kube-prometheus-stack --health --timeout 600
kubectl -n monitoring get pods
kubectl get crd | grep monitoring.coreos.com
```

---

## Lab 9.2 — Routes, récepteur d'alertes, explorer Prometheus (≈ 30 min)

Crée `platform/monitoring/` (Kustomize, namespace `monitoring`) : `routes.yaml` (HTTPRoutes `grafana.localhost` → `kps-grafana:80`, `prometheus.localhost` → `kps-prometheus:9090`, `alertmanager.localhost` → `kps-alertmanager:9093`), `alert-sink.yaml` + `alert_sink.py` (petit serveur Python qui affiche les alertes reçues), et l'Application `monitoring-config` dans `argocd/20-monitoring.yaml` (vague -2, `SkipDryRunOnMissingResource=true`).

```bash
git add . && git commit -m "feat(monitoring): routes et récepteur d'alertes" && git push
argocd app wait monitoring-config --health
kubectl -n monitoring logs deploy/alert-sink      # "alert-sink à l'écoute…" puis le Watchdog ? (non : routé vers null)
```

Ouvre http://prometheus.localhost :
- **Status → Targets** : quelles cibles ? lesquelles sont DOWN et pourquoi ?
- **Status → Service Discovery** : les labels `__meta_kubernetes_*` avant relabeling.
- **Status → TSDB Status** : nombre de séries, métriques à plus forte cardinalité.
- **Alerts** : les centaines de règles par défaut ; lesquelles sont déjà *firing* ?

---

## Lab 9.3 — Collecter les métriques de taskapi (≈ 20 min)

Ajoute `apps/taskapi/base/servicemonitor.yaml` (sélecteur `app.kubernetes.io/name: taskapi`, port **`http`**, `/metrics`, 15 s, annotation `SkipDryRunOnMissingResource=true`) et référence-le dans la `kustomization.yaml` de la base.

```bash
git add . && git commit -m "feat(taskapi): ServiceMonitor" && git push
```

Dans Prometheus → Targets : `serviceMonitor/taskapi-dev/taskapi/0` et `…prod…` doivent être **UP**. S'ils sont DOWN (timeout), relis la NetworkPolicy de la base (`monitoring` → port 8000).

Génère du trafic (laisse tourner dans un terminal pendant les labs suivants) :

```bash
python3 scripts/load.py http://taskapi-dev.localhost --duration 1800 --concurrency 4 &
python3 scripts/load.py http://taskapi.localhost     --duration 1800 --concurrency 2 &
```

---

## Lab 9.4 — PromQL : 15 requêtes (≈ 40 min)

Dans http://prometheus.localhost (onglet *Graph* pour voir les courbes). Écris la requête **avant** de déplier la solution.

<details><summary>1. Le nombre total de requêtes reçues par taskapi en dev depuis le démarrage des pods.</summary>

`sum(http_requests_total{namespace="taskapi-dev"})` — utile une fois, mais un counter brut n'a pas de sens dans un graphe.
</details>

<details><summary>2. Le débit (req/s) par environnement, sondes exclues.</summary>

`sum by (namespace) (rate(http_requests_total{job="taskapi", route!~"/metrics|/healthz|/readyz"}[5m]))`
</details>

<details><summary>3. Le débit par route en prod, trié décroissant.</summary>

`sort_desc(sum by (route) (rate(http_requests_total{namespace="taskapi-prod"}[5m])))`
</details>

<details><summary>4. Le nombre de requêtes 404 sur la dernière heure en dev.</summary>

`sum(increase(http_requests_total{namespace="taskapi-dev", status="404"}[1h]))`
</details>

<details><summary>5. Le taux d'erreurs 5xx par environnement (ratio 0-1).</summary>

`sum by (namespace) (rate(http_requests_total{job="taskapi",status=~"5.."}[5m])) / sum by (namespace) (rate(http_requests_total{job="taskapi"}[5m]))`
</details>

<details><summary>6. La latence p95 par route en dev.</summary>

`histogram_quantile(0.95, sum by (route, le) (rate(http_request_duration_seconds_bucket{namespace="taskapi-dev"}[5m])))`
</details>

<details><summary>7. La latence moyenne (pas un percentile) en prod.</summary>

`sum(rate(http_request_duration_seconds_sum{namespace="taskapi-prod"}[5m])) / sum(rate(http_request_duration_seconds_count{namespace="taskapi-prod"}[5m]))`
</details>

<details><summary>8. La proportion de requêtes servies en moins de 100 ms (Apdex simplifié).</summary>

`sum(rate(http_request_duration_seconds_bucket{le="0.1", job="taskapi"}[5m])) / sum(rate(http_request_duration_seconds_count{job="taskapi"}[5m]))`
</details>

<details><summary>9. Quelle version de taskapi tourne dans chaque environnement ?</summary>

`taskapi_build_info` (ou `count by (namespace, version) (taskapi_build_info)` pour voir les versions qui coexistent pendant un rollout).
</details>

<details><summary>10. La mémoire (working set) de chaque pod taskapi, en Mo.</summary>

`sum by (namespace, pod) (container_memory_working_set_bytes{container="taskapi"}) / 1024 / 1024`
</details>

<details><summary>11. Le % de la limite mémoire utilisé par chaque pod taskapi.</summary>

`sum by (namespace, pod) (container_memory_working_set_bytes{container="taskapi"}) / sum by (namespace, pod) (kube_pod_container_resource_limits{container="taskapi", resource="memory"})`
</details>

<details><summary>12. Le CPU consommé vs la request CPU (ratio) par pod.</summary>

`sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container="taskapi"}[5m])) / sum by (namespace, pod) (kube_pod_container_resource_requests{container="taskapi", resource="cpu"})`
</details>

<details><summary>13. Les 5 pods du cluster qui consomment le plus de mémoire.</summary>

`topk(5, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))`
</details>

<details><summary>14. Les pods qui ont redémarré dans la dernière heure.</summary>

`sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[1h])) > 0`
</details>

<details><summary>15. Le nombre de cibles DOWN, par job.</summary>

`count by (job) (up == 0)`
</details>

---

## Lab 9.5 — Règles d'enregistrement et d'alerte (≈ 30 min)

Crée `platform/monitoring/taskapi-rules.yaml` (PrometheusRule, ajoutée à la `kustomization.yaml`) :
- recording rules : `namespace:taskapi_http_requests:rate5m`, `namespace_route:taskapi_http_requests:rate5m`, `namespace:taskapi_http_errors:ratio_rate5m`, `namespace:taskapi_http_latency_seconds:p95_5m` ;
- alertes : `TaskapiDown` (critical, `for: 1m`), `TaskapiHighErrorRate` (> 5 %, `for: 2m`, critical), `TaskapiHighLatency` (p95 > 500 ms, `for: 5m`, warning), `TaskapiPodRestarting` — avec `summary`, `description` et **`runbook_url`** vers [RUNBOOKS.md](RUNBOOKS.md).

```bash
git add . && git commit -m "feat(monitoring): règles taskapi" && git push
# Prometheus → Status → Rules : tes groupes apparaissent ; Graph : interroge namespace:taskapi_http_errors:ratio_rate5m
```

**Déclenche une alerte pour de vrai :**

```bash
curl -s -X PUT http://taskapi-dev.localhost/chaos -H 'content-type: application/json' -d '{"error_rate":0.3}'
kubectl -n monitoring logs -f deploy/alert-sink          # dans un autre terminal
```

Suis l'alerte : Prometheus → *Alerts* (**pending** puis **firing** après 2 min) → http://alertmanager.localhost (groupée) → logs de `alert-sink` (🔥). Puis :

```bash
curl -s -X PUT http://taskapi-dev.localhost/chaos -H 'content-type: application/json' -d '{"error_rate":0}'
```

→ notification ✅ RESOLVED quelques minutes plus tard. (⚠ Le chaos est par pod : avec plusieurs réplicas, répète le PUT ou réduis à 1 réplica pour l'exercice.)

**Silence** : crée un silence d'1 h sur `TaskapiHighLatency` dans l'UI d'Alertmanager, puis injecte de la latence (`{"latency_ms":800}`) : l'alerte est *firing* dans Prometheus mais rien n'arrive au récepteur.

---

## Lab 9.6 — Dashboard as code (≈ 30 min)

Explore d'abord les dashboards fournis : http://grafana.localhost (admin / bootcamp) → *Dashboards* → « Kubernetes / Compute Resources / Namespace (Pods) », « Node Exporter / Nodes ».

Crée ensuite **dans l'UI** un dashboard « taskapi — RED » : variables `datasource` et `namespace`, 4 stats (req/s, taux d'erreur, p95, pods disponibles), graphes trafic par route, codes HTTP, p50/p95/p99, CPU, mémoire, redémarrages. Puis :

1. *Share → Export → Save to file* (ou *Edit → JSON Model*), enregistre dans `platform/monitoring/dashboards/taskapi-red.json` ;
2. ajoute un `configMapGenerator` (option `disableNameSuffixHash`, label `grafana_dashboard: "1"`) ;
3. pousse ; supprime le dashboard créé à la main ; il réapparaît, provisionné depuis Git (non modifiable durablement dans l'UI).

---

## 🏁 Challenge (sans guide)

1. Ajoute une alerte `TaskapiAbsent` basée sur `absent(up{job="taskapi", namespace="taskapi-prod"})` et prouve qu'elle se déclenche quand tu supprimes… non, pas le Deployment (Argo le recrée) : désactive l'auto-sync de `taskapi-prod`, scale à 0, constate, puis réactive.
2. Ajoute au dashboard une **annotation** des déploiements à partir de `changes(taskapi_build_info[1m]) > 0` (ou du nombre de versions distinctes).
3. Ajoute un **postgres-exporter** (chart `prometheus-community/prometheus-postgres-exporter`) en dev, avec son ServiceMonitor, et un panel « connexions actives ».

---

## ✅ Validation

```bash
make check-09
```
