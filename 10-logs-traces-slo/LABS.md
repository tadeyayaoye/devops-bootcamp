# Module 10 — Labs logs, traces, SLO, incident

> ⏱ ~3 h · Tout passe par le repo GitOps. Garde un générateur de charge actif en dev :
> `python3 scripts/load.py http://taskapi-dev.localhost --duration 3600 --concurrency 4 &`

---

## Lab 10.1 — Loki et Alloy : centraliser les logs (≈ 40 min)

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm search repo grafana-community/loki ; helm search repo grafana/alloy ; helm search repo grafana-community/tempo
```

> Si un chart est introuvable dans l'un des dépôts, cherche-le dans l'autre (`helm search repo alloy`) : les charts Grafana ont déménagé en 2026, c'est un bon exercice de veille.

Dans le repo GitOps :
1. `platform/values/loki.yaml` : `deploymentMode: Monolithic`, `auth_enabled: false`, stockage `filesystem`, schéma `tsdb`/`v13`, `singleBinary.replicas: 1` avec persistance, **tous les autres composants à 0**, gateway/caches/canary/minio désactivés ;
2. `platform/values/alloy.yaml` : contrôleur `deployment` (1 réplica), ports OTLP 4317/4318 en `extraPorts`, et une config Alloy : `discovery.kubernetes` → `discovery.relabel` (labels `namespace`, `pod`, `container`, `app`) → `loki.source.kubernetes` → `loki.process` (pour `app="taskapi"` : `stage.json` + label `level`) → `loki.write` ;
3. `argocd/30-logs-traces.yaml` : Applications `loki` et `alloy` (multi-sources, namespace `observability`, versions épinglées).

```bash
git add . && git commit -m "feat(observabilite): Loki + Alloy" && git push
argocd app wait loki alloy --health --timeout 600
kubectl -n observability get pods,svc                     # vérifie le nom/port du service Loki
kubectl -n observability logs deploy/alloy | tail          # erreurs de config ?
kubectl -n observability port-forward svc/alloy 12345 &    # UI d'Alloy : http://localhost:12345 (graphe des composants)
```

Ajoute la datasource **Loki** dans `platform/values/kube-prometheus-stack.yaml` (`grafana.additionalDataSources`, uid `loki`, URL du service), pousse, puis Grafana → **Explore** → Loki.

### LogQL (dans Explore)

```logql
{namespace="taskapi-dev"}
{app="taskapi", namespace="taskapi-dev"} | json
{app="taskapi"} | json | status >= 400 | line_format "{{.namespace}} {{.method}} {{.path}} → {{.status}} ({{.duration_ms}} ms)"
{app="taskapi"} | json | duration_ms > 200
sum by (namespace, status) (count_over_time({app="taskapi"} | json [5m]))
quantile_over_time(0.95, {app="taskapi", namespace="taskapi-dev"} | json | unwrap duration_ms [5m])
{namespace="argocd"} |= "level=error"
{namespace="kube-system", app="sealed-secrets"}
```

Pourquoi voit-on peu de logs de `taskapi-prod` ? (Indice : `LOG_LEVEL`.)

---

## Lab 10.2 — Traces avec OpenTelemetry et Tempo (≈ 40 min)

1. `platform/values/tempo.yaml` : rétention 24 h, `server.http_listen_port: 3200`, récepteurs OTLP gRPC/HTTP sur `0.0.0.0`, sans persistance ; ajoute l'Application `tempo` ;
2. complète la config Alloy : `otelcol.receiver.otlp` → `otelcol.processor.batch` → `otelcol.exporter.otlp` vers `tempo.observability.svc:4317` (TLS `insecure`) ;
3. active les traces dans l'application via les overlays (`envs/dev` et `envs/prod`, `configMapGenerator`) : `OTEL_ENABLED=true`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.observability.svc:4318` ;
4. ajoute la datasource **Tempo** (uid `tempo`, port 3200) et **corrèle** : *derived field* sur Loki (`"trace_id": ?"(\w+)"` → Tempo) et `tracesToLogsV2` sur Tempo (→ Loki, tag `service.name` ↦ `app`).

```bash
git add . && git commit -m "feat(observabilite): traces OpenTelemetry + Tempo, corrélation logs/traces" && git push
argocd app wait tempo alloy taskapi-dev --health
kubectl -n taskapi-dev rollout status deploy/taskapi       # le ConfigMap a changé → rollout automatique (hash !)
kubectl -n taskapi-dev logs deploy/taskapi | grep -m1 "traces OpenTelemetry activées"
```

Grafana → Explore → **Tempo** → *Search* : service `taskapi`. Ouvre une trace : span HTTP + spans SQL. Essaie TraceQL :

```traceql
{ resource.service.name = "taskapi" && duration > 100ms }
{ resource.service.name = "taskapi" && span.http.response.status_code >= 500 }
```

**Le parcours de corrélation** (à faire au moins 3 fois, c'est le geste d'investigation) :
1. Explore → Loki : `{app="taskapi", namespace="taskapi-dev"} | json | status >= 400` ;
2. déplie une ligne → bouton **Voir la trace** → la trace s'ouvre à droite (*split view*) ;
3. sur un span → **Logs for this span** → retour aux logs de cette requête.

Injecte de la latence et retrouve-la dans les traces :

```bash
curl -s -X PUT http://taskapi-dev.localhost/chaos -H 'content-type: application/json' -d '{"latency_ms":600}'
# TraceQL : { resource.service.name = "taskapi" && duration > 500ms }   → quel span porte la latence ?
curl -s -X PUT http://taskapi-dev.localhost/chaos -H 'content-type: application/json' -d '{"latency_ms":0}'
```

---

## Lab 10.3 — SLO et alertes de burn rate (≈ 40 min)

Crée `platform/monitoring/slo-rules.yaml` :
- SLI disponibilité `slo:taskapi_errors:ratio_rate{2m,5m,10m,30m,1h,6h}` (routes `/api/.*` uniquement) ;
- SLI latence `slo:taskapi_latency_good:ratio_rate5m` (bucket `le="0.25"`) ;
- alertes `TaskapiErrorBudgetBurnFast` (14,4 sur 1 h ET 5 min, critical), `TaskapiErrorBudgetBurnSlow` (6 sur 6 h ET 30 min, warning), et `TaskapiErrorBudgetBurnLab` (fenêtres 10 min / 2 min pour ne pas attendre une heure).

Ajoute le dashboard **taskapi — SLO** (`dashboards/taskapi-slo.json`) : disponibilité 1 h, budget restant sur 24 h, % de requêtes rapides, burn rate 5 min / 1 h / 6 h avec seuils 6 et 14,4.

```bash
git add . && git commit -m "feat(slo): SLO disponibilité et latence, alertes burn rate" && git push
```

Calcule à la main (et vérifie dans le dashboard) : avec un SLO à 99 % et un taux d'erreur de 30 %, quel est le burn rate ? En combien de temps le budget mensuel serait-il épuisé ?

<details><summary>Réponse</summary>

Burn rate = 0,30 / 0,01 = **30**. Budget de 30 jours épuisé en 30 / 30 = **1 jour** (24 h).
</details>

---

## Lab 10.4 — Exercice d'incident complet (≈ 45 min)

Tu es d'astreinte. Un·e collègue (ton autre terminal) va provoquer un incident **sans te dire lequel** — joue le jeu en lançant ce script et en ne lisant pas son contenu :

```bash
bash 10-logs-traces-slo/labs/incident.sh      # choisit au hasard une panne en dev
```

Puis, **sans regarder le script** :
1. Détecte : quelle alerte arrive dans `kubectl -n monitoring logs -f deploy/alert-sink` ? (si rien après 10 min : c'est une information sur tes alertes !)
2. Qualifie : dashboard RED + SLO → impact, début, routes touchées.
3. Investigue : logs → traces → cause.
4. Mitige (rollback Git, chaos à 0, scale…), vérifie le retour à la normale.
5. Rédige le postmortem dans `10-logs-traces-slo/postmortems/AAAA-MM-JJ-titre.md` à partir de [POSTMORTEM-TEMPLATE.md](POSTMORTEM-TEMPLATE.md), avec MTTD et MTTR mesurés.

Relance le script pour un 2ᵉ scénario.

---

## 🏁 Challenge (sans guide)

1. **Exemplars** : fais exposer à taskapi un exemplar (`trace_id`) sur l'histogramme de latence (format OpenMetrics) et affiche-les dans le panel de latence Grafana ; clique sur un point → trace.
2. **Metrics generator de Tempo** : active-le (remote write vers Prometheus, `enableRemoteWriteReceiver`) et affiche le **service graph** dans Grafana.
3. **Sloth** : réécris tes SLO au format Sloth (`PrometheusServiceLevel`) et compare les règles générées aux tiennes.

---

## ✅ Validation

```bash
make check-10
```
