#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
XLR=http://localhost:5516
export XLR

title "Module 16 — XL Release"
check "Le conteneur xl-release tourne" bash -c '[[ $(docker inspect -f "{{.State.Running}}" xl-release) == true ]]'
check "XL Release répond (localhost:5516)" http_ok "$XLR/"
check "XL Release est sur le réseau cicd (joint Jenkins)" bash -c 'docker inspect xl-release -f "{{json .NetworkSettings.Networks}}" | grep -q cicd'
if [[ -z "${XLR_ADMIN_PASSWORD:-}" ]]; then
  echo "  ⚠ exporte XLR_ADMIN_PASSWORD pour les vérifications suivantes"; summary; exit
fi
export XAUTH="admin:$XLR_ADMIN_PASSWORD"
check "Template « Livraison taskapi » présent" bash -c \
  'curl -fsS -u "$XAUTH" "$XLR/api/v1/templates" | jq -e "[.[].title] | any(test(\"Livraison taskapi\"))"'
check "Le template contient une gate" bash -c \
  'curl -fsS -u "$XAUTH" "$XLR/api/v1/templates" | jq -e "[.. | objects | select(.type? == \"xlrelease.GateTask\")] | length > 0"'
check "Le template contient une tâche Jenkins" bash -c \
  'curl -fsS -u "$XAUTH" "$XLR/api/v1/templates" | jq -e "[.. | objects | select((.type? // \"\") | test(\"jenkins\"; \"i\"))] | length > 0"'

title "Module 16 — As code"
check "Template exporté et versionné (release/xlr/*.yaml)" bash -c 'git -C $ROOT ls-files release/xlr | grep -q "\.yaml$"'
check "Le YAML déclare des phases" bash -c 'grep -q "phases:" $ROOT/release/xlr/*.yaml'

summary
