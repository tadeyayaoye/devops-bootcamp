#!/usr/bin/env bash
# Intègre les opérations du jour dans le « grand livre » (ledger).
# IDEMPOTENT : on retire d'abord les éventuelles lignes de cette date (relance après échec),
# puis on ajoute. Relancer 3 fois donne le même résultat qu'une fois.
# Le grand livre est partagé : un verrou (flock) protège les écritures concurrentes,
# et l'ordonnanceur limite l'accès avec une ressource / un pool à 1 place.
JOB=charger_transactions
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"
FICHIER="$IN/transactions_${DATE}.csv"
LEDGER="$WORK/grand_livre.csv"

[[ -s "$FICHIER" ]] || die "fichier absent : $FICHIER (le contrôle a-t-il tourné ?)" 10
touch "$LEDGER"

exec 9>"$LEDGER.lock"
flock -w 60 9 || die "grand livre verrouillé par un autre traitement depuis 60 s" 20

AVANT=$(grep -c ";${DATE};" "$LEDGER" || true)
grep -v ";${DATE};" "$LEDGER" > "$LEDGER.new" || true
awk -F';' 'NR > 1 && $1 != "TRL"' "$FICHIER" >> "$LEDGER.new"
mv "$LEDGER.new" "$LEDGER"
APRES=$(grep -c ";${DATE};" "$LEDGER" || true)

sleep "${BATCH_DUREE_CHARGEMENT:-5}"   # simule un traitement long (pour voir les pools/ressources)
log "grand livre : $AVANT → $APRES opérations pour le $DATE (total : $(wc -l < "$LEDGER") lignes)"
