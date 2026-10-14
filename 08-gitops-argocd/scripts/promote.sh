#!/usr/bin/env bash
# Promotion en prod : ouvre une Pull Request sur le repo GitOps qui passe envs/prod au tag
# ACTUELLEMENT déployé en dev (donc déjà construit, scanné, testé : « build once, deploy many »).
#   08-gitops-argocd/scripts/promote.sh            # promeut le tag courant de dev
#   08-gitops-argocd/scripts/promote.sh 1a2b3c4    # promeut un tag précis
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GITOPS_DIR="${GITOPS_DIR:-$ROOT/../devops-bootcamp-gitops}"
IMAGE=ghcr.io/tadeyayaoye/taskapi
cd "$GITOPS_DIR"

git switch main >/dev/null 2>&1 && git pull -q --rebase
TAG="${1:-$(yq '.images[] | select(.name == "'"$IMAGE"'") | .newTag' envs/dev/kustomization.yaml)}"
CURRENT=$(yq '.images[] | select(.name == "'"$IMAGE"'") | .newTag' envs/prod/kustomization.yaml)

[[ "$TAG" == "$CURRENT" ]] && { echo "La prod est déjà en $TAG"; exit 0; }
docker manifest inspect "$IMAGE:$TAG" >/dev/null || { echo "Image $IMAGE:$TAG introuvable sur GHCR"; exit 1; }

BRANCH="promote/prod-$TAG"
git switch -c "$BRANCH"
(cd envs/prod && kustomize edit set image "$IMAGE:$TAG")
git commit -qam "feat(prod): promotion de taskapi $CURRENT → $TAG"
git push -q -u origin "$BRANCH"

gh pr create --base main --head "$BRANCH" --label promotion \
  --title "Promotion prod : taskapi $TAG" \
  --body "Promotion en production de l'image \`$IMAGE:$TAG\`, validée en dev.

- Version actuelle en prod : \`$CURRENT\`
- Changements applicatifs : https://github.com/tadeyayaoye/devops-bootcamp/compare/$CURRENT...$TAG

Après merge, Argo CD synchronise \`taskapi-prod\`. Rollback = revert de cette PR."
git switch -q main
