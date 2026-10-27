#!/usr/bin/env bash
# Envoi des soldes à un partenaire (simule un outil de transfert MFT : CFT, Control-M MFT…).
# Bonne pratique : déposer le fichier, son empreinte, puis un FICHIER TÉMOIN (.ok) en dernier :
# le destinataire ne traite le fichier que lorsque le témoin est présent.
JOB=transferer_partenaire
source "$(dirname "$0")/common.sh"
need_date "${1:-}"
maybe_fail
DATE="$1"
SOLDES="$OUT/soldes_${DATE}.csv"
DEST="$OUT/partenaire"

[[ -s "$SOLDES" ]] || die "soldes absents : $SOLDES" 10

cp "$SOLDES" "$DEST/SOLDES_BQ_${DATE}.csv"
(cd "$DEST" && sha256sum "SOLDES_BQ_${DATE}.csv" > "SOLDES_BQ_${DATE}.csv.sha256")
touch "$DEST/SOLDES_BQ_${DATE}.ok"
log "transféré vers $DEST : SOLDES_BQ_${DATE}.csv (+ .sha256, + témoin .ok)"
