#!/usr/bin/env bash
# Génère un mot de passe aléatoire pour la base d'un environnement et l'écrit SCELLÉ dans le repo GitOps.
#   08-gitops-argocd/scripts/seal-db-secret.sh dev
#   08-gitops-argocd/scripts/seal-db-secret.sh prod
#
# Le mot de passe en clair n'est jamais écrit sur disque : il passe directement de openssl à kubeseal,
# qui chiffre avec la clé PUBLIQUE du contrôleur. Seul le contrôleur (dans le cluster) peut déchiffrer.
set -euo pipefail

ENV="${1:?usage: $0 <dev|prod>}"
NS="taskapi-${ENV}"
ROOT="$(git rev-parse --show-toplevel)"
GITOPS_DIR="${GITOPS_DIR:-$ROOT/../devops-bootcamp-gitops}"
OUT="$GITOPS_DIR/envs/$ENV/sealed-secret-db.yaml"

[[ -d "$GITOPS_DIR/envs/$ENV" ]] || { echo "Dossier $GITOPS_DIR/envs/$ENV introuvable"; exit 1; }

kubectl create secret generic taskapi-db \
  --namespace "$NS" \
  --from-literal=password="$(openssl rand -hex 16)" \
  --dry-run=client -o yaml \
| kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > "$OUT"

echo "✔ $OUT écrit (chiffré, commitable). Contenu :"
grep -E 'kind|name|namespace|password' "$OUT"
echo
echo "⚠ Changer le mot de passe d'une base DÉJÀ initialisée ne change pas celui stocké dans Postgres :"
echo "  en labo, supprime le PVC (kubectl -n $NS delete pvc data-postgres-0) pour repartir de zéro."
