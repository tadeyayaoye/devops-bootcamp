#!/usr/bin/env bash
# Petit client de l'API JSON-RPC de Zabbix.
#   export ZBX_URL=http://localhost:8091/api_jsonrpc.php
#   export ZBX_TOKEN=<API token créé dans l'UI : User settings → API tokens>   (ou laisse vide pour se loguer)
#   15-zabbix/scripts/zbx.sh apiinfo.version '{}'
#   15-zabbix/scripts/zbx.sh host.get '{"output":["host","status"]}'
#   15-zabbix/scripts/zbx.sh problem.get '{"recent":true}'
set -euo pipefail

ZBX_URL="${ZBX_URL:-http://localhost:8091/api_jsonrpc.php}"
METHOD="${1:?usage: zbx.sh <méthode> '<params JSON>'}"
PARAMS="${2:-{\}}"

call() {   # call <méthode> <params> [jeton]
  local auth=()
  [[ -n "${3:-}" ]] && auth=(-H "Authorization: Bearer $3")
  curl -fsS -X POST "$ZBX_URL" -H 'Content-Type: application/json-rpc' "${auth[@]}" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
}

# apiinfo.version et user.login s'appellent SANS authentification
if [[ "$METHOD" == "apiinfo.version" || "$METHOD" == "user.login" ]]; then
  call "$METHOD" "$PARAMS" | jq '.result // .error'
  exit
fi

TOKEN="${ZBX_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  [[ -n "${ZBX_PASSWORD:-}" ]] || { read -rsp "Mot de passe Zabbix de ${ZBX_USER:-Admin} : " ZBX_PASSWORD; echo >&2; }
  TOKEN=$(call user.login "{\"username\":\"${ZBX_USER:-Admin}\",\"password\":\"$ZBX_PASSWORD\"}" | jq -r '.result')
  [[ "$TOKEN" != "null" ]] || { echo "Échec d'authentification" >&2; exit 1; }
fi

call "$METHOD" "$PARAMS" "$TOKEN" | jq '.result // .error'
