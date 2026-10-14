#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

app_ok() {  # app_ok <application> → Synced ET Healthy
  local s h
  s=$(kubectl -n argocd get application "$1" -o jsonpath='{.status.sync.status}')
  h=$(kubectl -n argocd get application "$1" -o jsonpath='{.status.health.status}')
  [[ "$s" == Synced && "$h" == Healthy ]]
}
export -f app_ok

title "Module 08 — Argo CD"
check "Argo CD est déployé (argocd-server prêt)" k8s_ready argocd argocd-server
check "UI accessible sur http://argocd.localhost" http_ok http://argocd.localhost/healthz
check "Argo CD est géré par Terraform" bash -c 'terraform -chdir=$ROOT/infra/terraform/platform state list | grep -q "helm_release.argocd"'

title "Module 08 — Repo GitOps"
check "Le repo GitOps est cloné à côté" test -d "$GITOPS_DIR/.git"
check "bootstrap/root.yaml présent" test -f "$GITOPS_DIR/bootstrap/root.yaml"
check "Un ApplicationSet est défini" grep -rq "kind: ApplicationSet" "$GITOPS_DIR/argocd"
check "Secrets scellés pour dev et prod" bash -c 'test -f $GITOPS_DIR/envs/dev/sealed-secret-db.yaml && test -f $GITOPS_DIR/envs/prod/sealed-secret-db.yaml'
check "Aucun Secret en clair dans le repo GitOps" bash -c '! grep -rlE "^kind: Secret$" $GITOPS_DIR --include=*.yaml'
check "kustomize build OK pour dev et prod" bash -c 'kustomize build $GITOPS_DIR/envs/dev >/dev/null && kustomize build $GITOPS_DIR/envs/prod >/dev/null'

title "Module 08 — Applications"
for a in root sealed-secrets taskapi-dev taskapi-prod; do
  check "Application $a : Synced + Healthy" app_ok "$a"
done
check "taskapi-dev répond (http://taskapi-dev.localhost)" http_ok http://taskapi-dev.localhost/readyz
check "taskapi-prod répond (http://taskapi.localhost)" http_ok http://taskapi.localhost/readyz

title "Module 08 — Chaîne CI → GitOps"
check "Le Jenkinsfile met à jour le repo GitOps" grep -q "kustomize edit set image" "$ROOT/Jenkinsfile"
check "La CI a déjà commité dans le repo GitOps" bash -c 'git -C $GITOPS_DIR fetch -q && git -C $GITOPS_DIR log origin/main --author=jenkins-bot --oneline | grep -q .'
check "dev tourne sur un tag de commit (plus 'main')" bash -c '[[ $(yq ".images[0].newTag" $GITOPS_DIR/envs/dev/kustomization.yaml) =~ ^[0-9a-f]{7}$ ]]'
check "Une promotion prod a été mergée par PR" bash -c 'gh pr list -R tadeyayaoye/devops-bootcamp-gitops --state merged --label promotion --json number -q "length" | grep -qv "^0$"'

summary
