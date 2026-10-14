#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

G="http://grafana.localhost"
GAUTH="admin:bootcamp"
export G GAUTH
gq() { curl -fsS -u "$GAUTH" "$G/api/$1"; }
export -f gq

title "Module 10 — Composants"
for a in loki tempo alloy; do
  check "Application $a Synced + Healthy" bash -c "[[ \$(kubectl -n argocd get application $a -o jsonpath='{.status.sync.status}/{.status.health.status}') == Synced/Healthy ]]"
done
check "Datasource Loki provisionnée dans Grafana" bash -c 'gq datasources/uid/loki | jq -e ".type == \"loki\""'
check "Datasource Tempo provisionnée dans Grafana" bash -c 'gq datasources/uid/tempo | jq -e ".type == \"tempo\""'

title "Module 10 — Données"
check "Loki reçoit les logs de taskapi-dev" bash -c 'gq "datasources/proxy/uid/loki/loki/api/v1/label/namespace/values" | jq -e ".data | index(\"taskapi-dev\")"'
check "Les traces sont activées dans taskapi-dev" bash -c 'kubectl -n taskapi-dev exec deploy/taskapi -- printenv OTEL_ENABLED | grep -q true'
check "Tempo contient des traces de taskapi" bash -c 'gq "datasources/proxy/uid/tempo/api/search?tags=service.name%3Dtaskapi&limit=1" | jq -e ".traces | length > 0"'

title "Module 10 — SLO"
check "Règles SLO chargées dans Prometheus" bash -c 'curl -fsS http://prometheus.localhost/api/v1/rules | jq -e "[.data.groups[].name] | index(\"taskapi.slo.alerts\")"'
check "SLI calculé pour taskapi-dev" bash -c 'curl -fsS --get --data-urlencode "query=slo:taskapi_errors:ratio_rate5m{namespace=\"taskapi-dev\"}" http://prometheus.localhost/api/v1/query | jq -e ".data.result | length > 0"'
check "Dashboard SLO provisionné" bash -c 'gq "search?query=SLO" | jq -e "length > 0"'
check "Au moins un postmortem rédigé" bash -c 'ls $ROOT/10-logs-traces-slo/postmortems/*.md'

summary
