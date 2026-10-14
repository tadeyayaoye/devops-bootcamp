# Module 08 — Labs GitOps avec Argo CD

> ⏱ ~3 h 30 · Prérequis : image `ghcr.io/tadeyayaoye/taskapi:main` **publique** (module 07), Jenkins opérationnel.
> Tu travailles dans **deux repos** : `~/devops-bootcamp` et `~/devops-bootcamp-gitops`.

---

## Lab 8.1 — Installer Argo CD avec Terraform (≈ 25 min)

```bash
make tf-cluster                                 # si le cluster n'existe plus
helm search repo argo/argo-cd --versions | head -3
```

Dans `infra/terraform/platform/terraform.tfvars` : `enable_argocd = true` et épingle `chart_versions.argocd`.

```bash
make tf-platform
kubectl -n argocd get pods
make argocd-password                            # mot de passe admin initial
```

Ouvre http://argocd.localhost (admin / mot de passe ci-dessus). Puis la CLI :

```bash
kubectl -n argocd port-forward svc/argocd-server 8443:80 >/dev/null 2>&1 &
argocd login localhost:8443 --plaintext --username admin --password "$(make -s argocd-password)"
argocd account update-password        # change-le
argocd cluster list
argocd proj list
```

---

## Lab 8.2 — Construire le repo GitOps (≈ 40 min)

```bash
cd ~ && git clone https://github.com/tadeyayaoye/devops-bootcamp-gitops.git && cd devops-bootcamp-gitops
cp -r ~/devops-bootcamp/k8s/kustomize/{apps,envs} .
mkdir -p bootstrap argocd platform
```

Adapte les overlays `envs/dev` et `envs/prod` pour la vraie image :

```yaml
images:
  - name: ghcr.io/tadeyayaoye/taskapi
    newTag: main            # plus de newName: taskapi → on tire depuis GHCR
```

et ajoute `sealed-secret-db.yaml` dans `resources` (le fichier sera généré au lab 8.3).

Écris :
- `bootstrap/root.yaml` : Application `root` (projet `default`) qui synchronise **récursivement** `argocd/`, auto-sync + prune + selfHeal ;
- `argocd/00-projects.yaml` : AppProjects `platform` (tout permis) et `apps` (uniquement ton repo, uniquement les namespaces `taskapi-*`, seule ressource cluster autorisée : `Namespace`), vague `-10` ;
- `argocd/10-sealed-secrets.yaml` : Application du chart `sealed-secrets` (repo `https://bitnami-labs.github.io/sealed-secrets`) dans `kube-system`, `fullnameOverride: sealed-secrets-controller`, vague `-5`, **version épinglée**.

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets && helm search repo sealed-secrets
kustomize build envs/dev >/dev/null 2>&1 || echo "normal : sealed-secret-db.yaml manque encore"
git add bootstrap argocd && git commit -m "feat: bootstrap Argo CD (projets, sealed-secrets)" && git push
```

---

## Lab 8.3 — Bootstrap et secrets scellés (≈ 35 min)

```bash
kubectl apply -f bootstrap/root.yaml          # la SEULE commande kubectl apply de tout le module
argocd app list
argocd app get root
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
```

Regarde l'UI : `root` → `sealed-secrets`. Puis scelle les mots de passe des bases :

```bash
cd ~/devops-bootcamp
08-gitops-argocd/scripts/seal-db-secret.sh dev
08-gitops-argocd/scripts/seal-db-secret.sh prod
cd ~/devops-bootcamp-gitops
cat envs/dev/sealed-secret-db.yaml               # chiffré : commitable
kustomize build envs/dev | grep -c "kind:"       # le rendu fonctionne maintenant
```

Crée `argocd/50-taskapi.yaml` : un **ApplicationSet** (générateur `git` sur `envs/*`, `goTemplate: true`) qui produit `taskapi-dev` et `taskapi-prod` dans le projet `apps`, auto-sync, retry, et `ignoreDifferences` sur `/spec/replicas` des Deployments (HPA).

```bash
git add . && git commit -m "feat: taskapi dev et prod via ApplicationSet" && git push
argocd app list                          # taskapi-dev, taskapi-prod apparaissent (≤ 1 min)
argocd app wait taskapi-dev --health --timeout 300
kubectl -n taskapi-dev get sealedsecret,secret,pods
curl -s http://taskapi-dev.localhost/version
curl -s http://taskapi.localhost/version
```

Dans l'UI, ouvre `taskapi-dev` : observe l'**arbre des ressources** (Deployment → ReplicaSet → Pods), les **vagues** (Postgres avant l'API), les statuts **Synced/Healthy**.

---

## Lab 8.4 — Dérive et auto-réparation (≈ 25 min)

```bash
kubectl -n taskapi-dev delete svc taskapi                  # supprimé…
sleep 5; kubectl -n taskapi-dev get svc taskapi            # …et recréé par Argo CD (selfHeal)

kubectl -n taskapi-dev patch deploy taskapi --type json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"999Mi"}]'
argocd app get taskapi-dev | head -20                      # OutOfSync puis re-synchronisé
kubectl -n taskapi-dev get deploy taskapi -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo

kubectl -n taskapi-dev scale deploy taskapi --replicas=3   # replicas est ignoré : l'HPA décide
argocd app diff taskapi-dev
```

**Prune** : dans le repo GitOps, retire `autoscaling.yaml` de `apps/taskapi/base/kustomization.yaml`, pousse : l'HPA et le PDB disparaissent du cluster **en dev ET en prod** (base partagée !). Annule avec `git revert HEAD && git push`.

Question : en incident, comment empêcher temporairement Argo CD de « corriger » une modification d'urgence ? (`argocd app set taskapi-prod --sync-policy none`, puis reporter le correctif dans Git et réactiver.)

---

## Lab 8.5 — CI → GitOps → cluster (≈ 30 min)

Dans `~/devops-bootcamp`, ajoute au `Jenkinsfile` le stage **Mise à jour GitOps (dev)** (`when { branch 'main' }`) : clone du repo GitOps, `kustomize edit set image ghcr.io/tadeyayaoye/taskapi:${IMAGE_TAG}` dans `envs/dev`, commit par `jenkins-bot` (seulement s'il y a un changement), push avec le credential `github-token`.

Fais un vrai changement applicatif visible :

```bash
# app/src/taskapi/routes.py, fonction root : ajoute "message": "déployé par GitOps 🚀"
git commit -am "feat(api): message d'accueil" && git push
```

Suis toute la chaîne :

```bash
# 1. Jenkins : le build de main (≈ 3-6 min)
# 2. le repo GitOps reçoit le commit du bot :
cd ~/devops-bootcamp-gitops && git pull && git log --oneline -3 && cat envs/dev/kustomization.yaml | grep -A2 images
# 3. Argo CD synchronise (≤ 1 min) :
argocd app get taskapi-dev | grep -E "Sync Status|Health Status"
kubectl -n taskapi-dev rollout status deploy/taskapi
curl -s http://taskapi-dev.localhost/ | jq
```

Mesure le **lead time** (commit → en ligne en dev) : c'est une des métriques DORA.

---

## Lab 8.6 — Promotion en prod par Pull Request, puis rollback (≈ 25 min)

```bash
cd ~/devops-bootcamp
08-gitops-argocd/scripts/promote.sh          # lis le script d'abord !
gh pr list -R tadeyayaoye/devops-bootcamp-gitops
gh pr view -R tadeyayaoye/devops-bootcamp-gitops --web
```

Relis le diff de la PR (une seule ligne : le tag), puis merge :

```bash
gh pr merge -R tadeyayaoye/devops-bootcamp-gitops --squash --delete-branch
argocd app wait taskapi-prod --sync --health --timeout 300
curl -s http://taskapi.localhost/ | jq
```

**Rollback GitOps** : annule la promotion par un revert.

```bash
cd ~/devops-bootcamp-gitops && git pull
git revert --no-edit HEAD && git push
argocd app wait taskapi-prod --sync --health
curl -s http://taskapi.localhost/ | jq         # le message a disparu
argocd app history taskapi-prod
```

Remets la version promue (re-promote) avant de continuer.

---

## Lab 8.7 — Reprise après sinistre (≈ 20 min)

C'est LA démonstration de la valeur de GitOps + IaC :

```bash
cd ~/devops-bootcamp
make sealed-key-backup        # la clé privée Sealed Secrets, HORS du repo (sinon les secrets scellés sont perdus)
make tf-destroy               # 💥 plus de cluster
make up                       # tf-cluster + tf-platform + restauration de la clé + bootstrap GitOps
argocd login localhost:8443 --plaintext --username admin --password "$(make -s argocd-password)"   # après un nouveau port-forward
argocd app list
```

Chronomètre : combien de minutes pour retrouver dev et prod fonctionnels ? Les **données** de Postgres, elles, sont perdues : qu'aurait-il fallu en plus (sauvegardes externes, Velero, base managée) ?

---

## 🏁 Challenge (sans guide)

1. **Hook PostSync** : ajoute dans `apps/taskapi/base` un Job annoté `argocd.argoproj.io/hook: PostSync` (+ `hook-delete-policy: BeforeHookCreation`) qui vérifie `http://taskapi/readyz` après chaque sync. Pense à la NetworkPolicy (default deny !) et au profil `restricted`. Casse volontairement la readiness pour voir le sync échouer.
2. **Environnement éphémère** : ajoute un dossier `envs/staging` (copie de dev, autre hostname) et observe l'ApplicationSet créer `taskapi-staging` sans toucher à `argocd/`. Supprime le dossier : l'app disparaît.
3. **Sync window** : dans le projet `apps`, interdis les synchronisations automatiques de la prod le week-end (`syncWindows`). Vérifie avec `argocd proj windows list apps`.

---

## ✅ Validation

```bash
make check-08
```
