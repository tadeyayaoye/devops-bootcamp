#!/usr/bin/env bash
# Configure SonarQube par son API (au lieu de cliquer) :
#   1. change le mot de passe admin par défaut,
#   2. crée le webhook vers Jenkins (nécessaire à waitForQualityGate),
#   3. génère un token d'analyse et l'écrit dans ci/.env (sans l'afficher).
#
#   read -rs SONAR_ADMIN_PASSWORD && export SONAR_ADMIN_PASSWORD
#   ci/scripts/sonar-setup.sh
set -euo pipefail

S=http://localhost:9000
NEW="${SONAR_ADMIN_PASSWORD:?définis SONAR_ADMIN_PASSWORD (nouveau mot de passe admin, 12+ caractères)}"
ENV_FILE="$(git rev-parse --show-toplevel)/ci/.env"

echo "→ Attente de SonarQube (le premier démarrage peut prendre 2-3 min)…"
until curl -fsS "$S/api/system/status" 2>/dev/null | jq -e '.status == "UP"' >/dev/null; do sleep 5; done

if curl -fsS -u admin:admin "$S/api/authentication/validate" | jq -e '.valid' >/dev/null; then
  echo "→ Changement du mot de passe admin par défaut"
  curl -fsS -u admin:admin -X POST "$S/api/users/change_password" \
    --data-urlencode login=admin --data-urlencode previousPassword=admin --data-urlencode "password=$NEW"
fi
AUTH="admin:$NEW"

if ! curl -fsS -u "$AUTH" "$S/api/webhooks/list" | jq -e '.webhooks[] | select(.name == "jenkins")' >/dev/null; then
  echo "→ Création du webhook SonarQube → Jenkins"
  curl -fsS -u "$AUTH" -X POST "$S/api/webhooks/create" \
    --data-urlencode name=jenkins --data-urlencode url=http://jenkins:8080/sonarqube-webhook/ >/dev/null
fi

echo "→ Génération d'un token d'analyse global"
TOKEN=$(curl -fsS -u "$AUTH" -X POST "$S/api/user_tokens/generate" \
  --data-urlencode "name=jenkins-$(date +%Y%m%d-%H%M%S)" --data-urlencode type=GLOBAL_ANALYSIS_TOKEN | jq -r .token)
sed -i "s|^SONAR_TOKEN=.*|SONAR_TOKEN=${TOKEN}|" "$ENV_FILE"
unset TOKEN

echo "✔ Token écrit dans ci/.env. Recrée Jenkins pour qu'il le lise :"
echo "    docker compose -f ci/compose.yaml up -d jenkins"
