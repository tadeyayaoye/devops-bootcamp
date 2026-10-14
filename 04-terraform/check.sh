#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"
TF=infra/terraform

title "Module 04 — Code"
check "Module kind-cluster présent" test -f $TF/modules/kind-cluster/main.tf
check "Module platform présent" test -f $TF/modules/platform/main.tf
check "Bloc dynamic pour les workers" grep -q 'dynamic "node"' $TF/modules/kind-cluster/main.tf
check "terraform fmt OK" terraform fmt -recursive -check $TF
for s in cluster platform github; do
  check "Stack $s initialisée et valide" terraform -chdir=$TF/$s validate
done
check "Lock files commités" bash -c 'git ls-files infra/terraform | grep -q ".terraform.lock.hcl"'
check "Aucun state dans Git" bash -c '! git ls-files infra/terraform | grep -q tfstate'
check "Import déclaratif des repos GitHub" grep -q '^import {' $TF/github/main.tf
check "prevent_destroy sur les repos" grep -q prevent_destroy $TF/github/main.tf

title "Module 04 — Infra réelle"
check "State cluster : le cluster est géré par Terraform" bash -c 'terraform -chdir=$ROOT/infra/terraform/cluster state list | grep -q kind_cluster'
check "State platform : traefik géré par Terraform" bash -c 'terraform -chdir=$ROOT/infra/terraform/platform state list | grep -q helm_release.traefik'
check "Plan platform sans changement (pas de dérive)" terraform -chdir=$TF/platform plan -detailed-exitcode -input=false
hint "exit 2 = des changements en attente : apply ou corrige le code"
check "Versions des charts épinglées" bash -c 'grep -qE "traefik *= *\"[0-9]" $ROOT/infra/terraform/platform/terraform.tfvars'
check "Gateway joignable sur http://localhost" bash -c '[[ $(curl -s -o /dev/null -w "%{http_code}" http://localhost/) =~ ^(404|200)$ ]]'
check "State github : repos importés" bash -c 'terraform -chdir=$ROOT/infra/terraform/github state list | grep -q github_repository.repos'

summary
