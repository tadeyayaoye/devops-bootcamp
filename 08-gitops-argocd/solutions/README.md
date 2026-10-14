# Solutions du module 08

- `gitops-repo/` : contenu du repo **devops-bootcamp-gitops** à la fin du module (copié dans `../devops-bootcamp-gitops` par `./scripts/use-solution.sh 08`).
- `Jenkinsfile` : version finale du pipeline (ajoute le stage « Mise à jour GitOps (dev) »).

⚠ Les fichiers `envs/<env>/sealed-secret-db.yaml` ne sont **pas** fournis : ils sont propres à TON cluster (chiffrés avec la clé publique de TON contrôleur). Génère-les :

```bash
08-gitops-argocd/scripts/seal-db-secret.sh dev
08-gitops-argocd/scripts/seal-db-secret.sh prod
```

Ordre de mise en place :
1. pousser `bootstrap/`, `argocd/00-projects.yaml`, `argocd/10-sealed-secrets.yaml` ;
2. `kubectl apply -f bootstrap/root.yaml` et attendre le contrôleur sealed-secrets ;
3. sceller les secrets, puis pousser `apps/`, `envs/` et `argocd/50-taskapi.yaml`.
