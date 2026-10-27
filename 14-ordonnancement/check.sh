#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
A="$ROOT/batch/airflow"
export A
af() { docker compose --project-directory "$A" exec -T airflow-scheduler airflow "$@"; }
export -f af
# list-runs : DAG en argument positionnel (Airflow 3) ou via -d (Airflow 2)
runs() { af dags list-runs "$1" -o json 2>/dev/null || af dags list-runs -d "$1" -o json; }
export -f runs

title "Module 14 — Airflow"
check "batch/airflow contient docker-compose.yaml + override" bash -c 'test -f $A/docker-compose.yaml && test -f $A/docker-compose.override.yaml'
check "Airflow répond (http://localhost:8090)" http_ok http://localhost:8090/api/v2/monitor/health
hint "cd batch/airflow && docker compose up -d"
check "Pool db_batch à 1 place" bash -c 'af pools get db_batch -o json | jq -e ".[0].slots == 1"'
check "Aucune erreur d'import de DAG" bash -c '[[ $(af dags list-import-errors -o json | jq length) -eq 0 ]]'
check "DAG arrete_comptable présent" bash -c 'af dags list -o json | jq -e "[.[].dag_id] | index(\"arrete_comptable\")"'
check "DAG reporting_reglementaire présent" bash -c 'af dags list -o json | jq -e "[.[].dag_id] | index(\"reporting_reglementaire\")"'
check "Au moins un arrêté terminé avec succès" bash -c 'runs arrete_comptable | jq -e "[.[] | select(.state == \"success\")] | length > 0"'
check "Le reporting réglementaire a été déclenché par l'Asset" bash -c 'runs reporting_reglementaire | jq -e "length > 0"'
check "Les fichiers du partenaire ont un témoin .ok" bash -c 'ls $A/data/out/partenaire/*.ok'
check "Grand livre sans doublon (chaque id unique)" bash -c '[[ -z $(cut -d";" -f1 $A/data/work/grand_livre.csv | sort | uniq -d) ]]'

title "Module 14 — Control-M Jobs-as-Code"
check "batch/controlm/ARRETE_COMPTABLE.json est du JSON valide" jq . "$ROOT/batch/controlm/ARRETE_COMPTABLE.json"
check "Il contient un File Watcher, une ressource et des conditions" bash -c \
  'f=$ROOT/batch/controlm/ARRETE_COMPTABLE.json; grep -q FileWatcher $f && grep -q "Resource:" $f && grep -q AddEvents $f && grep -q WaitForEvents $f'

summary
