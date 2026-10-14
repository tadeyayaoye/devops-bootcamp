#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

title "Module 02 — Cluster"
check "Le cluster kind 'bootcamp' existe" bash -c 'kind get clusters | grep -qx bootcamp'
hint "make cluster-up"
check "Contexte kubectl = kind-bootcamp" bash -c '[[ $(kubectl config current-context) == kind-bootcamp ]]'
check "3 nœuds Ready" bash -c '[[ $(kubectl get nodes --no-headers | grep -c " Ready") -eq 3 ]]'

title "Module 02 — Manifests"
check "k8s/m02/ contient des manifests" bash -c 'ls k8s/m02/*.yaml'
check "Les manifests sont valides (dry-run serveur)" kubectl apply --dry-run=server -f k8s/m02/
check "Le Secret n'est pas dans Git" bash -c '! grep -rl "kind: Secret" k8s/m02/'
check "Le Deployment a des probes readiness ET liveness" bash -c 'grep -q readinessProbe k8s/m02/*.yaml && grep -q livenessProbe k8s/m02/*.yaml'
check "Le Deployment a des requests et une limite mémoire" bash -c 'grep -q requests: k8s/m02/*.yaml && grep -q "memory:" k8s/m02/*.yaml'

title "Module 02 — Déploiement"
check "Le Secret taskapi-db existe dans le cluster" kubectl -n taskapi get secret taskapi-db
check "postgres est disponible" k8s_ready taskapi postgres
check "taskapi est disponible (2 réplicas prêts mini)" bash -c '[[ $(kubectl -n taskapi get deploy taskapi -o jsonpath="{.status.readyReplicas}") -ge 2 ]]'
check "Le Service taskapi a des endpoints" bash -c 'kubectl -n taskapi get endpointslices -l kubernetes.io/service-name=taskapi -o jsonpath="{.items[*].endpoints[*].addresses}" | grep -q "[0-9]"'
check "taskapi répond /readyz depuis l'intérieur du cluster" \
  kubectl -n taskapi exec deploy/taskapi -- python -c "import urllib.request; urllib.request.urlopen('http://taskapi/readyz', timeout=3)"
check "Le namespace debug-lab a été nettoyé" bash -c '! kubectl get ns debug-lab'

summary
