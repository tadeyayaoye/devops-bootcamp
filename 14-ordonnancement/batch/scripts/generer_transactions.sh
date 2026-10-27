#!/usr/bin/env bash
# Simule le PARTENAIRE qui dépose le fichier des transactions de la journée.
#   generer_transactions.sh AAAAMMJJ [nb_lignes] [ok|corrompu]
# Format : en-tête, une ligne par opération, puis un enregistrement de fin (trailer)
#   TRL;<nombre de lignes>;<somme des montants>   ← totaux de contrôle, classiques en banque
JOB=generer_transactions
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
DATE="$1"; NB="${2:-500}"; MODE="${3:-ok}"

FICHIER="$IN/transactions_${DATE}.csv"
TMP="$IN/.transactions_${DATE}.csv.tmp"

{
  echo "id;date_operation;compte;montant_centimes"
  for i in $(seq 1 "$NB"); do
    printf '%s-%06d;%s;FR76%010d;%d\n' "$DATE" "$i" "$DATE" $((RANDOM % 40 + 1)) $(( (RANDOM * 7 % 200000) - 100000 ))
  done
} > "$TMP"

COUNT="$NB"
SOMME=$(awk -F';' 'NR > 1 { s += $4 } END { print s + 0 }' "$TMP")
[[ "$MODE" == "corrompu" ]] && COUNT=$((COUNT - 1))   # trailer volontairement faux
echo "TRL;${COUNT};${SOMME}" >> "$TMP"

# Écriture ATOMIQUE : on écrit sous un nom temporaire puis on renomme.
# Ainsi le capteur de fichier ne voit jamais un fichier à moitié écrit.
mv "$TMP" "$FICHIER"
log "fichier déposé : $FICHIER ($NB opérations, mode $MODE)"
