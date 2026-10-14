# Solutions du module 09

Fichiers à ajouter au repo GitOps (`./scripts/use-solution.sh 09` les copie sans écraser l'existant) :

| Fichier | Rôle |
|---|---|
| `argocd/20-monitoring.yaml` | Applications `kube-prometheus-stack` (multi-sources) et `monitoring-config` |
| `platform/values/kube-prometheus-stack.yaml` | valeurs adaptées à kind/WSL et 16 Go |
| `platform/monitoring/` | routes Grafana/Prometheus/Alertmanager, récepteur d'alertes, règles, dashboard |
| `apps/taskapi/base/servicemonitor.yaml` + `kustomization.yaml` | collecte des métriques de taskapi |

⚠ `apps/taskapi/base/kustomization.yaml` existe déjà chez toi : avec `--force` il est remplacé (la seule différence est l'ajout de `servicemonitor.yaml` dans `resources`).

Après copie : épingle la version du chart dans `argocd/20-monitoring.yaml`, commit, push.
