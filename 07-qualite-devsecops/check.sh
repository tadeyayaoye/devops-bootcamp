#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

JPASS=$(grep -E '^JENKINS_ADMIN_PASSWORD=' ci/.env 2>/dev/null | cut -d= -f2-)
export JAUTH="admin:${JPASS}"
japi() { curl -fsS -u "$JAUTH" "http://localhost:8080/$1"; }
export -f japi

title "Module 07 — SonarQube"
check "SonarQube est UP" bash -c 'curl -fsS http://localhost:9000/api/system/status | jq -e ".status == \"UP\""'
hint "make sonar-up"
check "app/sonar-project.properties présent" test -f app/sonar-project.properties
check "Le projet taskapi a été analysé" bash -c 'curl -fsS "http://localhost:9000/api/qualitygates/project_status?projectKey=taskapi" | jq -e ".projectStatus.status"'
check "La quality gate de taskapi est verte (OK)" bash -c 'curl -fsS "http://localhost:9000/api/qualitygates/project_status?projectKey=taskapi" | jq -e ".projectStatus.status == \"OK\""'
check "La couverture est importée (> 0 %)" bash -c 'curl -fsS "http://localhost:9000/api/measures/component?component=taskapi&metricKeys=coverage" | jq -e "(.component.measures[0].value | tonumber) > 0"'

title "Module 07 — Pipeline Jenkins"
check "Le Jenkinsfile contient gitleaks, hadolint, Trivy et le quality gate" bash -c 'grep -q gitleaks Jenkinsfile && grep -q hadolint Jenkinsfile && grep -qi trivy Jenkinsfile && grep -q waitForQualityGate Jenkinsfile'
check "Les outils de sécurité sont épinglés (pas de :latest)" bash -c '! grep -E "(trivy|gitleaks|hadolint)[^ ]*:latest" Jenkinsfile'
check "Le dernier build de main est vert" bash -c 'japi job/taskapi/job/main/lastBuild/api/json | jq -e ".result == \"SUCCESS\""'
check "Un SBOM est archivé" bash -c 'japi job/taskapi/job/main/lastSuccessfulBuild/api/json | jq -e "[.artifacts[].fileName] | any(startswith(\"sbom\"))"'

title "Module 07 — Registre et GitHub Actions"
check "Image publique ghcr.io/tadeyayaoye/taskapi:main téléchargeable" docker manifest inspect ghcr.io/tadeyayaoye/taskapi:main
check "Workflow GitHub Actions présent" test -f .github/workflows/ci.yml
check "Actions épinglées par SHA" bash -c '! grep -E "uses: [^ ]+@v[0-9]" .github/workflows/ci.yml'
check "Le dernier run Actions sur main a réussi" bash -c '[[ $(gh run list -w "CI taskapi" -b main -L 1 --json conclusion -q ".[0].conclusion") == success ]]'
check "Dependabot configuré" test -f .github/dependabot.yml

summary
