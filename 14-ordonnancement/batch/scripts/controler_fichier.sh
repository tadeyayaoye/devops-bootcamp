#!/usr/bin/env bash
# Contrôle de cohérence du fichier reçu : en-tête, trailer, nombre de lignes et total de contrôle.
# Un fichier faux ne se corrige pas tout seul : ce job ne doit PAS être relancé automatiquement.
JOB=controler_fichier
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"
FICHIER="$IN/transactions_${DATE}.csv"

[[ -s "$FICHIER" ]] || die "fichier absent ou vide : $FICHIER" 10
[[ "$(head -1 "$FICHIER")" == "id;date_operation;compte;montant_centimes" ]] || die "en-tête invalide" 11

TRAILER=$(tail -1 "$FICHIER")
[[ "$TRAILER" == TRL\;* ]] || die "enregistrement de fin (TRL) absent : fichier tronqué ?" 12
ATTENDU_NB=$(cut -d';' -f2 <<<"$TRAILER")
ATTENDU_SOMME=$(cut -d';' -f3 <<<"$TRAILER")

REEL_NB=$(awk 'NR > 1' "$FICHIER" | grep -vc '^TRL;' || true)
REEL_SOMME=$(awk -F';' 'NR > 1 && $1 != "TRL" { s += $4 } END { print s + 0 }' "$FICHIER")
DATES_FAUSSES=$(awk -F';' -v d="$DATE" 'NR > 1 && $1 != "TRL" && $2 != d' "$FICHIER" | wc -l)

log "lignes : attendu=$ATTENDU_NB réel=$REEL_NB | somme : attendu=$ATTENDU_SOMME réel=$REEL_SOMME"
[[ "$REEL_NB" == "$ATTENDU_NB" ]] || die "nombre de lignes incohérent avec le trailer" 13
[[ "$REEL_SOMME" == "$ATTENDU_SOMME" ]] || die "total de contrôle incohérent avec le trailer" 14
[[ "$DATES_FAUSSES" -eq 0 ]] || die "$DATES_FAUSSES opérations ne sont pas datées du $DATE" 15

log "fichier conforme ✔"
