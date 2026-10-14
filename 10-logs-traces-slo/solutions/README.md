# Solutions du module 10

Fichiers du repo GitOps :

| Fichier | Rôle |
|---|---|
| `argocd/30-logs-traces.yaml` | Applications `loki`, `tempo` (charts grafana-community) et `alloy` (chart grafana) |
| `platform/values/{loki,tempo,alloy}.yaml` | valeurs (Loki monolithique, Tempo OTLP, pipeline Alloy logs + traces) |
| `platform/values/kube-prometheus-stack.yaml` | version du module 09 + datasources Loki/Tempo corrélées |
| `platform/monitoring/slo-rules.yaml`, `dashboards/taskapi-slo.json`, `kustomization.yaml` | SLO, burn rate, dashboard SLO |
| `envs/{dev,prod}/kustomization.yaml` | ajout de `OTEL_ENABLED` et `OTEL_EXPORTER_OTLP_ENDPOINT` |

⚠ **N'écrase pas aveuglément `envs/*/kustomization.yaml` avec `--force`** : la version fournie remet le tag d'image à `main`, alors que la CI (dev) et tes promotions (prod) y ont écrit un SHA. Ajoute plutôt à la main les deux lignes `OTEL_*` dans le `configMapGenerator` de chaque overlay.

Après copie : épingle les versions des trois charts, vérifie les noms de services (`kubectl -n observability get svc`) par rapport aux URLs utilisées (Loki `:3100`, Tempo `:3200`/`:4317`), commit, push.
