#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

# Identifiants Jenkins depuis ci/.env (jamais affichés)
JPASS=$(grep -E '^JENKINS_ADMIN_PASSWORD=' ci/.env 2>/dev/null | cut -d= -f2-)
export JAUTH="admin:${JPASS}"
japi() { curl -fsS -u "$JAUTH" "http://localhost:8080/$1"; }
export -f japi

title "Module 06 — Plateforme CI as code"
check "ci/compose.yaml valide" docker compose -f ci/compose.yaml config -q
check "ci/.env n'est pas suivi par Git" bash -c '! git ls-files --error-unmatch ci/.env'
check "JCasC présent" test -f ci/jenkins/casc/jenkins.yaml
check "plugins.txt présent" test -f ci/jenkins/plugins.txt
check "Le conteneur jenkins tourne" bash -c '[[ $(docker inspect -f "{{.State.Running}}" jenkins) == true ]]'
check "Jenkins accessible avec le compte admin" japi api/json
check "Jenkins peut parler à Docker" docker exec jenkins docker version
check "Le réseau cicd existe" docker network inspect cicd

title "Module 06 — Pipeline"
check "Jenkinsfile à la racine" test -f Jenkinsfile
check "Le Jenkinsfile utilise un agent Docker" grep -q "docker {" Jenkinsfile
check "Le job multibranch taskapi existe" japi job/taskapi/api/json
check "Une branche main a été construite" japi job/taskapi/job/main/lastBuild/api/json
check "Le dernier build de main est vert" bash -c 'japi job/taskapi/job/main/lastBuild/api/json | jq -e ".result == \"SUCCESS\""'
check "Des résultats de tests sont publiés" japi job/taskapi/job/main/lastBuild/testReport/api/json

summary
