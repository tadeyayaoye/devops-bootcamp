# Auto-évaluation

Pour chaque ligne, coche seulement si tu peux le faire **maintenant, sans documentation** (ou l'expliquer à voix haute en moins de 2 minutes). Puis reporte un niveau de 1 à 5 dans [PROGRESSION.md](../PROGRESSION.md).

## Linux, Git
- [ ] Expliquer SIGTERM vs SIGKILL et ce que fait `docker stop` / la suppression d'un pod
- [ ] Écrire un script bash robuste (`set -euo pipefail`, `trap`, arguments obligatoires)
- [ ] Résoudre un conflit de rebase et récupérer des commits perdus avec `reflog`
- [ ] Expliquer merge vs rebase, revert vs reset, et choisir selon le contexte

## Docker
- [ ] Expliquer namespaces, cgroups, couches OverlayFS
- [ ] Écrire un Dockerfile multi-stage, non-root, cache optimisé, forme exec
- [ ] Diagnostiquer un exit code 137 et un conteneur lent à s'arrêter
- [ ] Écrire un compose.yaml avec healthcheck, depends_on conditionnel, secret, réseau interne

## Kubernetes
- [ ] Raconter le chemin d'un `kubectl apply` jusqu'au pod Running
- [ ] Écrire Deployment + Service + probes + resources sans modèle
- [ ] Diagnostiquer Pending / ImagePullBackOff / CrashLoopBackOff / OOMKilled / Service sans endpoints
- [ ] Expliquer requests/limits/QoS et le calcul de l'HPA
- [ ] Écrire une NetworkPolicy default-deny + une règle d'autorisation
- [ ] Expliquer Gateway API (GatewayClass / Gateway / HTTPRoute) et pourquoi elle remplace Ingress
- [ ] Choisir entre Helm et Kustomize et expliquer pourquoi

## Terraform
- [ ] Expliquer le state, le locking, le drift, et pourquoi séparer les stacks
- [ ] Utiliser `for_each`, `dynamic`, `moved`, `import`
- [ ] Lire un plan et repérer un remplacement dangereux
- [ ] Expliquer Terraform vs OpenTofu vs Ansible

## Ansible
- [ ] Structurer un projet (inventaire, group_vars, rôles, handlers, templates)
- [ ] Garantir l'idempotence et le prouver
- [ ] Utiliser Vault et `no_log`
- [ ] Faire un déploiement progressif (`serial`, vérification de santé)

## CI/CD
- [ ] Écrire un Jenkinsfile déclaratif (agents Docker, post, when, withCredentials)
- [ ] Expliquer Jenkins as code (image, plugins, JCasC, Job DSL)
- [ ] Écrire le même pipeline en GitHub Actions avec permissions minimales et actions épinglées par SHA
- [ ] Expliquer « build once, deploy many » et les 4 métriques DORA

## Qualité, sécurité
- [ ] Expliquer quality gate et « clean as you code »
- [ ] Trier un rapport Trivy et justifier une politique de gate
- [ ] Expliquer SBOM, signature cosign, SLSA, et l'incident Trivy de mars 2026
- [ ] Réagir correctement à un secret commité

## GitOps
- [ ] Expliquer les 4 principes et l'intérêt du modèle pull
- [ ] Construire un repo GitOps (base/overlays, app-of-apps, ApplicationSet)
- [ ] Promouvoir par PR et faire un rollback par revert
- [ ] Comparer Sealed Secrets, SOPS, External Secrets

## Observabilité
- [ ] Écrire en PromQL : débit, taux d'erreur, p95, % de la limite mémoire
- [ ] Écrire une règle d'alerte avec `for`, labels, runbook
- [ ] Expliquer le routage/groupement/inhibition d'Alertmanager
- [ ] Écrire en LogQL : filtre JSON + métrique dérivée des logs
- [ ] Expliquer trace / span / propagation et OpenTelemetry
- [ ] Définir SLI/SLO/budget, calculer un burn rate, expliquer l'alerte multi-fenêtres
- [ ] Mener un incident et écrire un postmortem blameless

**Lecture** : chaque case non cochée = un point de révision. Choisis les 5 plus importants pour ton prochain poste et note-les dans PROGRESSION.md.
