#!/usr/bin/env bash
# Configure PAR L'API ce que le lab 15.3 fait à la main :
#   groupe d'hôtes "Bootcamp/Linux" + action d'auto-enregistrement
#   (HostMetadata contient "bootcamp" → créer l'hôte, l'ajouter au groupe, lier le template Linux actif).
# Idempotent : ne recrée pas ce qui existe déjà.
#   export ZBX_TOKEN=…   (ou ZBX_PASSWORD=…)
#   15-zabbix/solutions/scripts/zbx-autoregistration.sh
set -euo pipefail
ZBX="$(git rev-parse --show-toplevel)/15-zabbix/scripts/zbx.sh"

GROUP="Bootcamp/Linux"
TEMPLATE="Linux by Zabbix agent active"
ACTION="Auto-enregistrement bootcamp"

GROUPID=$($ZBX hostgroup.get "{\"filter\":{\"name\":[\"$GROUP\"]}}" | jq -r '.[0].groupid // empty')
if [[ -z "$GROUPID" ]]; then
  GROUPID=$($ZBX hostgroup.create "{\"name\":\"$GROUP\"}" | jq -r '.groupids[0]')
  echo "groupe créé : $GROUP ($GROUPID)"
fi

TEMPLATEID=$($ZBX template.get "{\"filter\":{\"host\":[\"$TEMPLATE\"]}}" | jq -r '.[0].templateid // empty')
[[ -n "$TEMPLATEID" ]] || { echo "template introuvable : $TEMPLATE"; exit 1; }

if [[ -n $($ZBX action.get "{\"filter\":{\"name\":[\"$ACTION\"]}}" | jq -r '.[0].actionid // empty') ]]; then
  echo "action déjà présente : $ACTION"
  exit 0
fi

# eventsource 2 = auto-enregistrement ; conditiontype 24 = métadonnées d'hôte ; operator 2 = contient
# operationtype 2 = ajouter l'hôte ; 4 = ajouter à un groupe ; 6 = lier un template
$ZBX action.create "$(cat <<EOF
{
  "name": "$ACTION",
  "eventsource": 2,
  "filter": {
    "evaltype": 0,
    "conditions": [ { "conditiontype": 24, "operator": 2, "value": "bootcamp" } ]
  },
  "operations": [
    { "operationtype": 2 },
    { "operationtype": 4, "opgroup":    [ { "groupid": "$GROUPID" } ] },
    { "operationtype": 6, "optemplate": [ { "templateid": "$TEMPLATEID" } ] }
  ]
}
EOF
)"
echo "action créée : $ACTION"
