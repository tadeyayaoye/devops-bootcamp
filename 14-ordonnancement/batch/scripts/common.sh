#!/usr/bin/env bash
# Fonctions communes aux jobs batch de la chaîne ARRETE_COMPTABLE.
# Chaque job : un argument = la date d'ordonnancement AAAAMMJJ (ODATE / logical date),
# code retour 0 = OK, ≠ 0 = KO, logs explicites sur stdout (la « sysout » du job).
set -euo pipefail

BATCH_DATA="${BATCH_DATA:-/opt/airflow/data}"
IN="$BATCH_DATA/in"
WORK="$BATCH_DATA/work"
OUT="$BATCH_DATA/out"
ARCHIVE="$BATCH_DATA/archive"
mkdir -p "$IN" "$WORK" "$OUT/partenaire" "$ARCHIVE"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "${JOB:-batch}" "$*"; }
die() { log "ERREUR : $1"; exit "${2:-1}"; }

need_date() {
  [[ "${1:-}" =~ ^[0-9]{8}$ ]] || die "usage : $(basename "$0") AAAAMMJJ" 2
}

# Panne simulée pour les exercices : touch $BATCH_DATA/fail_<job> pour faire échouer ce job
maybe_fail() {
  if [[ -f "$BATCH_DATA/fail_${JOB}" ]]; then
    die "échec simulé (fichier $BATCH_DATA/fail_${JOB} présent)" 99
  fi
}
