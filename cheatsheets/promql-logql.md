# PromQL, LogQL, TraceQL — fiche mémo

## PromQL

```promql
# Débit (RED : Rate)
sum by (route) (rate(http_requests_total{job="taskapi"}[5m]))
# Erreurs (RED : Errors)
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
# Latence (RED : Duration) — garder "le" !
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
# Moyenne
rate(x_sum[5m]) / rate(x_count[5m])
# Événements sur une période
increase(http_requests_total[1h])
# Ressources
sum by (pod) (rate(container_cpu_usage_seconds_total{container="app"}[5m]))
sum by (pod) (container_memory_working_set_bytes{container="app"})
  / sum by (pod) (kube_pod_container_resource_limits{resource="memory", container="app"})
# État
up == 0                          absent(up{job="x"})                count by (job) (up == 0)
increase(kube_pod_container_status_restarts_total[1h]) > 0
kube_deployment_status_replicas_available / kube_deployment_spec_replicas
predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0
topk(5, …)   sort_desc(…)   avg_over_time(x[1h])   max_over_time   offset 1d   changes(x[1h])
```

Règles : `rate()` puis `sum()` · fenêtre ≥ 4 × scrape interval · counters → rate/increase · gauges → valeur ou *_over_time · labels à faible cardinalité.

Burn rate (SLO 99 %) : `ratio_erreurs / 0.01` · page si > 14.4 (1 h ET 5 min) · ticket si > 6 (6 h ET 30 min).

## LogQL (Loki)

```logql
{namespace="taskapi-prod", app="taskapi"}                       # sélecteur de flux (obligatoire)
{app="taskapi"} |= "error" != "healthz"                         # contient / ne contient pas
{app="taskapi"} |~ "status\":5\\d\\d"                           # regex
{app="taskapi"} | json | status >= 500 and duration_ms > 200
{app="taskapi"} | json | line_format "{{.method}} {{.path}} {{.status}}"
{app="taskapi"} | logfmt | level="error"
sum by (status) (count_over_time({app="taskapi"} | json [5m]))
sum(rate({app="taskapi"} | json | status >= 500 [5m]))
quantile_over_time(0.95, {app="taskapi"} | json | unwrap duration_ms [5m])
topk(5, sum by (pod) (rate({namespace="x"}[5m])))
```

## TraceQL (Tempo)

```traceql
{ resource.service.name = "taskapi" }
{ resource.service.name = "taskapi" && duration > 500ms }
{ span.http.response.status_code >= 500 }
{ span.http.route = "/api/tasks/{task_id}" && status = error }
{ resource.service.name = "taskapi" } >> { span.db.system = "postgresql" && duration > 100ms }
```
