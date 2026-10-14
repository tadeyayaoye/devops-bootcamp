#!/usr/bin/env bash
# Vérification de bout en bout : toute la chaîne doit être verte.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

JPASS=$(grep -E '^JENKINS_ADMIN_PASSWORD=' ci/.env 2>/dev/null | cut -d= -f2-)
export JAUTH="admin:${JPASS}"

title "Infrastructure"
check "Cluster géré par Terraform" bash -c 'terraform -chdir=infra/terraform/cluster state list | grep -q kind_cluster'
check "3 nœuds Ready" bash -c '[[ $(kubectl get nodes --no-headers | grep -c " Ready") -eq 3 ]]'
check "Toutes les Applications Argo CD Synced + Healthy" bash -c \
  '[[ -z $(kubectl -n argocd get applications -o jsonpath="{range .items[*]}{.status.sync.status}/{.status.health.status}{\"\n\"}{end}" | grep -v "Synced/Healthy") ]]'

title "Application"
check "dev répond" http_ok http://taskapi-dev.localhost/readyz
check "prod répond" http_ok http://taskapi.localhost/readyz
check "La fonctionnalité /api/tasks/stats est en prod" http_ok http://taskapi.localhost/api/tasks/stats
check "dev et prod tournent sur des tags de commit (pas 'main')" bash -c \
  'for e in dev prod; do [[ $(yq ".images[0].newTag" $GITOPS_DIR/envs/$e/kustomization.yaml) =~ ^[0-9a-f]{7}$ ]] || exit 1; done'

title "CI/CD"
check "Jenkins : dernier build de main vert" bash -c 'curl -fsS -u "$JAUTH" http://localhost:8080/job/taskapi/job/main/lastBuild/api/json | jq -e ".result == \"SUCCESS\""'
check "SonarQube : quality gate OK" bash -c 'curl -fsS "http://localhost:9000/api/qualitygates/project_status?projectKey=taskapi" | jq -e ".projectStatus.status == \"OK\""'
check "GitHub Actions : dernier run de main vert" bash -c '[[ $(gh run list -w "CI taskapi" -b main -L 1 --json conclusion -q ".[0].conclusion") == success ]]'

title "Observabilité"
check "Cibles taskapi UP" bash -c 'curl -fsS --get --data-urlencode "query=sum(up{job=\"taskapi\"})" http://prometheus.localhost/api/v1/query | jq -e "(.data.result[0].value[1]|tonumber) >= 2"'
check "Aucune alerte taskapi critique active" bash -c '! curl -fsS http://prometheus.localhost/api/v1/alerts | jq -e "[.data.alerts[] | select(.state==\"firing\" and .labels.severity==\"critical\" and (.labels.alertname|startswith(\"Taskapi\")))] | length > 0"'
check "Logs et traces disponibles" bash -c 'curl -fsS -u admin:bootcamp "http://grafana.localhost/api/datasources/uid/tempo" >/dev/null && curl -fsS -u admin:bootcamp "http://grafana.localhost/api/datasources/uid/loki" >/dev/null'

title "Traces du travail"
check "Journal du projet final rédigé" test -s 11-projet-final/JOURNAL.md
check "Au moins 2 postmortems" bash -c '[[ $(ls 10-logs-traces-slo/postmortems/*.md 2>/dev/null | wc -l) -ge 2 ]]'
check "Tag bootcamp-final posé" bash -c 'git tag -l bootcamp-final | grep -q .'

summary
