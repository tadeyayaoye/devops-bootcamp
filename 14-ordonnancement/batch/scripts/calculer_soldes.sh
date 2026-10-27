#!/usr/bin/env bash
# Calcule le solde de chaque compte à la date d'arrêté (cumul de toutes les opérations ≤ DATE).
JOB=calculer_soldes
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"
LEDGER="$WORK/grand_livre.csv"
SORTIE="$OUT/soldes_${DATE}.csv"

[[ -s "$LEDGER" ]] || die "grand livre vide" 10

exec 9>"$LEDGER.lock"
flock -s -w 60 9 || die "grand livre verrouillé" 20      # verrou PARTAGÉ : lecture

{
  echo "compte;solde_centimes;nb_operations"
  awk -F';' -v d="$DATE" '$2 <= d { solde[$3] += $4; nb[$3]++ }
    END { for (c in solde) printf "%s;%d;%d\n", c, solde[c], nb[c] }' "$LEDGER" | sort
} > "$SORTIE.tmp"
mv "$SORTIE.tmp" "$SORTIE"

sleep "${BATCH_DUREE_CALCUL:-3}"
log "soldes écrits : $SORTIE ($(($(wc -l < "$SORTIE") - 1)) comptes)"
