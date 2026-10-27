#!/usr/bin/env bash
# Fin de chaîne : archive le fichier reçu (compressé) et purge les archives trop anciennes.
#   archiver.sh AAAAMMJJ [retention_jours]
JOB=archiver
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"; RETENTION="${2:-30}"
FICHIER="$IN/transactions_${DATE}.csv"

if [[ -f "$FICHIER" ]]; then
  gzip -c "$FICHIER" > "$ARCHIVE/transactions_${DATE}.csv.gz"
  rm -f "$FICHIER"
  log "archivé : $ARCHIVE/transactions_${DATE}.csv.gz"
else
  log "rien à archiver (déjà fait ? relance idempotente)"
fi
PURGES=$(find "$ARCHIVE" -name '*.gz' -mtime +"$RETENTION" -print -delete | wc -l)
log "$PURGES archive(s) de plus de $RETENTION jours purgée(s)"
