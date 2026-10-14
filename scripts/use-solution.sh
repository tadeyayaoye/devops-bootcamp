#!/usr/bin/env bash
# Copie les solutions d'un module à leur place dans le repo (et dans le repo GitOps).
#
#   ./scripts/use-solution.sh 03            # ne remplace pas les fichiers existants
#   ./scripts/use-solution.sh 03 --force    # remplace tout
#
# Les dossiers solutions/ reflètent la racine du repo :
#   NN-module/solutions/app/Dockerfile        → app/Dockerfile
#   NN-module/solutions/gitops-repo/...       → ../devops-bootcamp-gitops/...
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GITOPS_DIR="${GITOPS_DIR:-$ROOT/../devops-bootcamp-gitops}"
mod="${1:?usage: $0 <numéro de module> [--force]}"
force="${2:-}"

dir=$(compgen -G "$ROOT/${mod}-*" | head -1 || true)
[[ -n "$dir" && -d "$dir/solutions" ]] || { echo "Pas de dossier solutions/ pour le module $mod"; exit 1; }

copy() {   # copy <source> <destination-dir>
  if [[ "$force" == "--force" ]]; then
    cp -r "$1" "$2/"
  else
    cp -r --update=none "$1" "$2/"
  fi
}

shopt -s dotglob nullglob
for entry in "$dir"/solutions/*; do
  name=$(basename "$entry")
  case "$name" in
    README.md) continue ;;
    gitops-repo)
      [[ -d "$GITOPS_DIR" ]] || { echo "⚠ $GITOPS_DIR introuvable : clone d'abord le repo GitOps (module 08)"; continue; }
      for g in "$entry"/*; do copy "$g" "$GITOPS_DIR"; done
      echo "✔ gitops-repo → $GITOPS_DIR"
      ;;
    *)
      copy "$entry" "$ROOT"
      echo "✔ $name → $ROOT/$name"
      ;;
  esac
done

echo
echo "Fait. Regarde ce qui a changé avec : git status && git diff"
[[ "$force" == "--force" ]] || echo "(les fichiers déjà présents n'ont pas été écrasés — ajoute --force si besoin)"
