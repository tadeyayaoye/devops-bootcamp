#!/usr/bin/env bash
# Reporting de fin de journée (simplifié) : volumes, totaux, comptes débiteurs.
JOB=generer_reporting
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"
FICHIER="$IN/transactions_${DATE}.csv"
SOLDES="$OUT/soldes_${DATE}.csv"
SORTIE="$OUT/reporting_${DATE}.txt"

[[ -s "$SOLDES" ]] || die "soldes absents : $SOLDES" 10

NB_OPS=$(awk -F';' 'NR > 1 && $1 != "TRL"' "$FICHIER" | wc -l)
CREDITS=$(awk -F';' 'NR > 1 && $1 != "TRL" && $4 > 0 { s += $4 } END { printf "%.2f", s / 100 }' "$FICHIER")
DEBITS=$(awk -F';' 'NR > 1 && $1 != "TRL" && $4 < 0 { s += $4 } END { printf "%.2f", s / 100 }' "$FICHIER")
DEBITEURS=$(awk -F';' 'NR > 1 && $2 < 0' "$SOLDES" | wc -l)

cat > "$SORTIE" <<EOF
=== REPORTING DE FIN DE JOURNÉE — arrêté du $DATE ===
Opérations du jour      : $NB_OPS
Total crédits (EUR)     : $CREDITS
Total débits  (EUR)     : $DEBITS
Comptes débiteurs       : $DEBITEURS
Généré le               : $(date '+%F %T')
EOF
log "reporting écrit : $SORTIE"
