#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

title "Module 01 — Dockerfile"
check "app/Dockerfile existe" test -f app/Dockerfile
check "app/.dockerignore existe et exclut .env et .venv" bash -c 'grep -q "\.env" app/.dockerignore && grep -q "\.venv" app/.dockerignore'
check "Dockerfile multi-stage (au moins 2 FROM)" bash -c '[[ $(grep -c "^FROM" app/Dockerfile) -ge 2 ]]'
check "ENTRYPOINT/CMD en forme exec" grep -qE '^(ENTRYPOINT|CMD) \[' app/Dockerfile
check "Instruction USER numérique" grep -qE '^USER [0-9]+' app/Dockerfile
check "hadolint sans erreur" hadolint --failure-threshold error app/Dockerfile

title "Module 01 — Image taskapi:dev"
check "L'image taskapi:dev existe" docker image inspect taskapi:dev
hint "docker build -t taskapi:dev app/"
check "Elle ne tourne pas en root" bash -c '[[ "$(docker run --rm --entrypoint id taskapi:dev -u)" != "0" ]]'
check "Elle fait moins de 300 Mo" bash -c '[[ $(docker image inspect taskapi:dev --format "{{.Size}}") -lt 300000000 ]]'
check "Elle définit un HEALTHCHECK" bash -c '[[ "$(docker image inspect taskapi:dev --format "{{.Config.Healthcheck}}")" != "<nil>" ]]'
check "Label org.opencontainers.image.source présent" bash -c 'docker image inspect taskapi:dev --format "{{json .Config.Labels}}" | grep -q image.source'
check "Aucune CVE CRITICAL corrigeable" trivy image --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 taskapi:dev

title "Module 01 — Compose"
check "compose.yaml existe à la racine" test -f compose.yaml
check "compose.yaml est valide" docker compose config -q
check "Le secret n'est pas commité" bash -c '! git ls-files --error-unmatch secrets/db_password.txt'
check "La stack tourne : /readyz répond 200" http_ok http://localhost:8000/readyz
hint "docker compose up -d --build"
check "Le service db est healthy" bash -c 'docker compose ps db --format "{{.Health}}" | grep -q healthy'

summary
