# Exercices à blanc

> Règles : **aucune documentation, aucun copier-coller, aucun fichier existant ouvert**. Un minuteur par exercice. Écris dans `/tmp/blanc/`, puis compare avec ce que tu as produit pendant le bootcamp et valide avec l'outil (`hadolint`, `kubectl apply --dry-run=server`, `terraform validate`, `ansible-lint`…). L'objectif n'est pas la perfection mais de **mesurer ce qui est acquis**.

| # | Exercice | Temps | Validation |
|---|---|---|---|
| 1 | **Dockerfile** multi-stage pour une appli Python : venv dans le builder, image slim, utilisateur 10001, healthcheck, ENTRYPOINT exec, labels OCI | 12 min | `hadolint`, build, `docker run --user`, temps de rebuild après modif du code |
| 2 | **compose.yaml** : appli + Postgres, healthcheck, depends_on healthy, volume, secret fichier, réseau backend interne | 10 min | `docker compose config`, `up`, `/readyz` |
| 3 | **Manifests K8s** : Namespace (PSS restricted), Deployment (2 réplicas, maxUnavailable 0, 3 probes, resources, securityContext complet), Service, HTTPRoute | 20 min | `kubectl apply --dry-run=server`, déploiement réel |
| 4 | **HPA + PDB + NetworkPolicy** (default deny + Gateway + monitoring) | 10 min | `--dry-run=server` |
| 5 | **Kustomize** : base + overlay prod (namespace, image, replicas, configMapGenerator merge, patch JSON) | 12 min | `kustomize build` |
| 6 | **Terraform** : module avec variable `map(object)` validée, `for_each`, output, + appel du module | 15 min | `terraform validate`, `plan` |
| 7 | **Ansible** : rôle nginx (tasks, handler avec listen, template avec validate) + playbook | 15 min | `ansible-lint`, run + 2ᵉ run `changed=0` |
| 8 | **Jenkinsfile** : options, stage de tests dans un agent docker avec post junit, build, push conditionné à main avec withCredentials | 15 min | linter déclaratif (`curl -X POST -F "jenkinsfile=<Jenkinsfile" localhost:8080/pipeline-model-converter/validate` avec authentification) |
| 9 | **GitHub Actions** : workflow test + build/push GHCR, permissions minimales, concurrency | 12 min | `actionlint` (bonus) |
| 10 | **Argo CD** : Application avec auto-sync/prune/selfHeal + ApplicationSet générateur git directories | 10 min | `kubectl apply --dry-run=server` |
| 11 | **PromQL** : débit par route, taux d'erreur, p99, top 3 pods en CPU, cibles DOWN | 10 min | Prometheus |
| 12 | **PrometheusRule** : 1 recording rule + 1 alerte burn rate multi-fenêtres | 10 min | `promtool check rules` (bonus) |
| 13 | **LogQL** : erreurs JSON d'un namespace, formatage de ligne, p95 depuis `duration_ms` | 8 min | Grafana Explore |

**Après** : pour chaque exercice, note ce que tu as dû chercher → c'est exactement ta liste de révision.
