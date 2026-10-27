#!/usr/bin/env bash
# Chaîne aval REPORTING_REGLEMENTAIRE : consolide tous les reportings journaliers disponibles.
# Elle ne connaît pas la date : elle est déclenchée par la fin de l'arrêté (condition / Asset).
JOB=consolider_reporting
source "$(dirname "$0")/common.sh"
maybe_fail
SORTIE="$OUT/consolidation_reglementaire.txt"

shopt -s nullglob
RAPPORTS=("$OUT"/reporting_*.txt)
[[ ${#RAPPORTS[@]} -gt 0 ]] || die "aucun reporting journalier disponible" 10

{
  echo "=== CONSOLIDATION RÉGLEMENTAIRE — $(date '+%F %T') ==="
  for r in "${RAPPORTS[@]}"; do
    printf '%s : %s opérations\n' "$(basename "$r" .txt | cut -d_ -f2)" "$(grep 'Opérations du jour' "$r" | awk -F': ' '{print $2}')"
  done
} > "$SORTIE"
log "consolidation : ${#RAPPORTS[@]} journée(s) → $SORTIE"
