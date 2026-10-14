#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

PROM=http://prometheus.localhost
promq() { curl -fsS --get --data-urlencode "query=$1" "$PROM/api/v1/query"; }
export PROM; export -f promq

title "Module 09 — Stack de supervision"
for a in kube-prometheus-stack monitoring-config; do
  check "Application $a Synced + Healthy" bash -c "[[ \$(kubectl -n argocd get application $a -o jsonpath='{.status.sync.status}/{.status.health.status}') == Synced/Healthy ]]"
done
check "Prometheus accessible (prometheus.localhost)" http_ok "$PROM/-/ready"
check "Grafana accessible (grafana.localhost)" http_ok http://grafana.localhost/api/health
check "Alertmanager accessible (alertmanager.localhost)" http_ok http://alertmanager.localhost/-/ready
check "Version du chart épinglée (pas de '*')" bash -c '! grep -q "targetRevision: \"\*\"" $GITOPS_DIR/argocd/20-monitoring.yaml'

title "Module 09 — Collecte et règles"
check "Cibles taskapi UP en dev et prod" bash -c 'promq "sum by (namespace) (up{job=\"taskapi\"})" | jq -e "[.data.result[] | select((.value[1]|tonumber) >= 1)] | length >= 2"'
check "Recording rule taskapi présente" bash -c 'promq "namespace:taskapi_http_requests:rate5m" | jq -e ".data.result | length > 0"'
check "Alertes taskapi chargées" bash -c 'curl -fsS $PROM/api/v1/rules | jq -e "[.data.groups[].rules[] | select(.name|startswith(\"Taskapi\"))] | length >= 3"'
check "Les alertes ont un runbook_url" bash -c 'curl -fsS $PROM/api/v1/rules | jq -e "[.data.groups[].rules[] | select(.name|startswith(\"Taskapi\")) | .annotations.runbook_url] | all"'
check "Le récepteur d'alertes tourne" k8s_ready monitoring alert-sink

title "Module 09 — Dashboards as code"
check "Dashboard JSON versionné dans le repo GitOps" bash -c 'ls $GITOPS_DIR/platform/monitoring/dashboards/*.json'
check "Dashboard taskapi provisionné dans Grafana" bash -c 'curl -fsS -u admin:bootcamp "http://grafana.localhost/api/search?query=taskapi" | jq -e "length > 0"'

summary
