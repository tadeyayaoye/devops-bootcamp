#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
ZBX="$ROOT/15-zabbix/scripts/zbx.sh"
export ZBX

title "Module 15 — Plateforme Zabbix"
check "Le frontend Zabbix répond (localhost:8091)" http_ok http://localhost:8091/
check "L'API répond" bash -c '$ZBX apiinfo.version "{}" | grep -q "7\."'
if [[ -z "${ZBX_TOKEN:-}${ZBX_PASSWORD:-}" ]]; then
  echo "  ⚠ exporte ZBX_TOKEN (API token) pour les vérifications suivantes"; summary; exit
fi
check "Le mot de passe Admin par défaut a été changé" bash -c \
  '! curl -fsS -X POST http://localhost:8091/api_jsonrpc.php -H "Content-Type: application/json-rpc" \
     -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"Admin\",\"password\":\"zabbix\"},\"id\":1}" | jq -e .result'

title "Module 15 — Hôtes et collecte"
for h in web1 web2 db1; do
  check "Hôte $h enregistré et disponible" bash -c "\$ZBX host.get '{\"filter\":{\"host\":[\"$h\"]},\"selectInterfaces\":[\"available\"],\"output\":[\"host\",\"active_available\"]}' | jq -e '.[0].active_available == \"1\" or .[0].interfaces[0].available == \"1\"'"
done
check "Action d'auto-enregistrement présente" bash -c '$ZBX action.get "{\"filter\":{\"eventsource\":2}}" | jq -e "length > 0"'
check "Template taskapi présent" bash -c '$ZBX template.get "{\"search\":{\"host\":\"taskapi\"}}" | jq -e "length > 0"'
check "L'item taskapi.readyz de web1 vaut 200" bash -c \
  '$ZBX item.get "{\"host\":\"web1\",\"search\":{\"key_\":\"taskapi.readyz\"},\"output\":[\"lastvalue\"]}" | jq -e ".[0].lastvalue == \"200\""'
check "Un web scenario existe" bash -c '$ZBX httptest.get "{}" | jq -e "length > 0"'

title "Module 15 — Alerting"
check "Media type webhook configuré" bash -c '$ZBX mediatype.get "{\"filter\":{\"type\":4}}" | jq -e "length > 0"'
check "Une action sur triggers existe" bash -c '$ZBX action.get "{\"filter\":{\"eventsource\":0}}" | jq -e "[.[] | select(.name | test(\"Report problems\") | not)] | length > 0"'
check "Une maintenance a été créée" bash -c '$ZBX maintenance.get "{}" | jq -e "length > 0"'

summary
