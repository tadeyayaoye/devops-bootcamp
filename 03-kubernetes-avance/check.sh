#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
cd "$ROOT"

title "Module 03 — Plateforme"
check "metrics-server répond (kubectl top nodes)" kubectl top nodes
check "Traefik est déployé" k8s_ready traefik traefik
check "Les CRD Gateway API sont installées" kubectl get crd httproutes.gateway.networking.k8s.io
check "GatewayClass traefik acceptée" bash -c 'kubectl get gatewayclass traefik -o jsonpath="{.status.conditions[?(@.type==\"Accepted\")].status}" | grep -q True'
check "Gateway main programmée" bash -c 'kubectl -n traefik get gateway main -o jsonpath="{.status.conditions[?(@.type==\"Programmed\")].status}" | grep -q True'

title "Module 03 — Workloads"
check "Namespace taskapi en Pod Security restricted" bash -c '[[ $(kubectl get ns taskapi -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/enforce}") == restricted ]]'
check "Postgres est un StatefulSet prêt" bash -c '[[ $(kubectl -n taskapi get sts postgres -o jsonpath="{.status.readyReplicas}") == 1 ]]'
check "Le PVC de Postgres est Bound" bash -c 'kubectl -n taskapi get pvc data-postgres-0 -o jsonpath="{.status.phase}" | grep -q Bound'
check "Le CronJob pg-backup existe" kubectl -n taskapi get cronjob pg-backup
check "Le Deployment taskapi tourne en lecture seule et non-root" bash -c 'kubectl -n taskapi get deploy taskapi -o yaml | grep -q "readOnlyRootFilesystem: true"'
check "Un HPA cible taskapi et lit le CPU" bash -c 'kubectl -n taskapi get hpa taskapi -o jsonpath="{.status.currentMetrics[0].resource.current.averageUtilization}" | grep -q "[0-9]"'
check "Un PDB protège taskapi" kubectl -n taskapi get pdb taskapi
check "http://taskapi.localhost répond via la Gateway" http_ok http://taskapi.localhost/readyz

title "Module 03 — Sécurité"
check "Le SA lecteur peut lister les pods" bash -c '[[ $(kubectl auth can-i list pods -n taskapi --as system:serviceaccount:taskapi:lecteur) == yes ]]'
check "Le SA lecteur ne peut PAS lire les secrets" bash -c '[[ $(kubectl auth can-i get secrets -n taskapi --as system:serviceaccount:taskapi:lecteur) == no ]]'
check "Une NetworkPolicy default-deny existe" kubectl -n taskapi get networkpolicy default-deny-ingress

title "Module 03 — Packaging"
check "Le chart Helm passe helm lint" helm lint charts/taskapi
check "Le chart se rend sans erreur" bash -c 'helm template demo charts/taskapi >/dev/null'
check "kustomize build dev OK" bash -c 'kustomize build k8s/kustomize/envs/dev >/dev/null'
check "kustomize build prod OK" bash -c 'kustomize build k8s/kustomize/envs/prod >/dev/null'
check "Le ConfigMap Kustomize est suffixé d'un hash" bash -c 'kustomize build k8s/kustomize/envs/dev | grep -qE "name: taskapi-config-[a-z0-9]{10}"'

summary
