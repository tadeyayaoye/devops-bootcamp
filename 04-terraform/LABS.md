# Module 04 — Labs Terraform

> ⏱ ~3 h · Tout le code va dans `infra/terraform/`. Le cluster manuel des modules 02-03 va être **remplacé** par un cluster géré par Terraform.

---

## Lab 4.1 — Bac à sable : HCL, state, drift (≈ 40 min)

Crée `infra/terraform/sandbox/` avec les providers `hashicorp/local` et `hashicorp/random` :

- une variable `environments` de type `map(object({ replicas = number, debug = optional(bool, false) }))` avec une **validation** (1 ≤ replicas ≤ 10) ;
- un `random_password` par environnement (`for_each`) ;
- un `local_file` par environnement généré avec `templatefile()` (fichier `config.env.tftpl`) ;
- un fichier `index.txt` qui liste les autres (dépendance implicite) ;
- des outputs, dont un `sensitive`.

```bash
cd infra/terraform/sandbox
terraform init                 # télécharge les providers, crée .terraform.lock.hcl
cat .terraform.lock.hcl        # versions + hash : à commiter
terraform fmt && terraform validate
terraform plan                 # lis chaque ligne
terraform apply
cat generated/dev.env
terraform output
terraform output -json db_passwords     # le "sensitive" n'est qu'un masque d'affichage…
grep -A3 '"result"' terraform.tfstate | head    # … le secret est EN CLAIR dans le state
terraform graph | head -30              # le graphe de dépendances (format DOT)
```

**Idempotence et drift :**

```bash
terraform plan                          # "No changes"
echo "HACK=1" >> generated/prod.env     # modification manuelle
terraform plan                          # Terraform voit la dérive et veut corriger
terraform apply -auto-approve
```

**Changer une clé `for_each`** : ajoute un environnement `staging`, plan/apply. Puis renomme `prod` en `production` : que propose le plan ? Annule avec un bloc `moved` :

```hcl
moved {
  from = local_file.config["prod"]
  to   = local_file.config["production"]
}
```

(`random_password` aussi.) Relance `plan` : plus de destruction. Enfin, `terraform apply -var 'environments={"x"={replicas=42}}'` : la validation doit refuser.

```bash
terraform destroy
cd -
```

---

## Lab 4.2 — Le cluster en code (≈ 35 min)

On supprime le cluster « à la main » (tout ce qui est dedans est reconstructible : c'est l'intérêt) :

```bash
kind delete cluster --name bootcamp
```

Écris le module `infra/terraform/modules/kind-cluster/` (`main.tf`, `variables.tf`, `outputs.tf`) :
- provider `tehcyx/kind` (`~> 0.11`), ressource `kind_cluster` avec `wait_for_ready = true` ;
- un nœud control-plane avec deux `extra_port_mappings` (30080→`var.http_port`, 30443→`var.https_port`) ;
- un bloc **`dynamic "node"`** qui crée `var.worker_count` workers ;
- variable `worker_count` validée (0 à 4).

Puis la stack `infra/terraform/cluster/main.tf` qui appelle le module.

```bash
cd infra/terraform/cluster
terraform init
terraform plan
terraform apply                     # ~1-2 min
terraform state list
terraform output
kubectl get nodes
cd -
```

Questions : que se passe-t-il si tu changes `worker_count` de 2 à 1 et fais un `plan` ? (Lis bien : `forces replacement`.) Pourquoi est-ce acceptable pour kind mais serait grave pour un cluster de prod ?

---

## Lab 4.3 — La plateforme en code (≈ 45 min)

Écris le module `infra/terraform/modules/platform/` :

- `kubernetes_namespace_v1` pour `traefik` et `monitoring` (+ `argocd` si `enable_argocd`) via `for_each` sur une `local` ;
- `helm_release` **metrics-server** et **traefik** (réutilise tes values du module 03, rangées dans `values/`) ;
- un **chart local** `charts/gateway/` contenant ta GatewayClass + Gateway, installé par un `helm_release` avec `depends_on = [helm_release.traefik]` (pourquoi est-il indispensable ici ?) ;
- (préparation du module 08) `helm_release` **argo-cd** et un chart local `charts/routes/` générique (liste de routes en values), tous deux avec `count = var.enable_argocd ? 1 : 0`.

Puis la stack `infra/terraform/platform/` : providers `helm` (**v3** : `kubernetes = { config_path, config_context }`) et `kubernetes`, configurés sur le contexte `kind-bootcamp`.

```bash
cd infra/terraform/platform
terraform init
terraform apply
helm list -A                         # les releases créées par Terraform
kubectl get gateway -A
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   # 404 Traefik : la Gateway répond
cd -
```

Redéploie l'application (manifests du module 03) sur ce nouveau cluster :

```bash
docker images taskapi:dev && kind load docker-image taskapi:dev --name bootcamp
kubectl apply -f k8s/m03/00-namespace.yaml
kubectl -n taskapi create secret generic taskapi-db --from-literal=password="$(openssl rand -hex 16)"
kubectl apply -f k8s/m03/
curl -s http://taskapi.localhost/version
```

**Drift côté Kubernetes** :

```bash
helm -n traefik upgrade traefik traefik/traefik --reuse-values --set logs.access.enabled=false
cd infra/terraform/platform && terraform plan     # Terraform détecte la modification hors code
terraform apply && cd -
```

---

## Lab 4.4 — Épingler les versions (≈ 15 min)

En sortie de `terraform apply`, regarde `terraform output releases` : des versions ont été choisies **pour toi** (les dernières). Demain, elles changeront.

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm search repo traefik/traefik --versions | head -3
helm search repo metrics-server/metrics-server --versions | head -3
helm search repo argo/argo-cd --versions | head -3
```

Copie `terraform.tfvars.example` en `terraform.tfvars`, renseigne `chart_versions` avec **les versions actuellement installées**, et vérifie que `terraform plan` affiche « No changes ». Commite `.terraform.lock.hcl` et `terraform.tfvars` (aucun secret dedans).

---

## Lab 4.5 — GitHub as code : import (≈ 35 min)

Les deux repos existent déjà. On va les **adopter** sans les recréer.

```bash
mkdir -p infra/terraform/github && cd infra/terraform/github
export GITHUB_TOKEN=$(gh auth token)       # jamais dans un fichier
```

Écris `main.tf` et `variables.tf` :
- provider `integrations/github` (`~> 6.0`), `owner = var.github_owner` ;
- deux blocs **`import`** vers `github_repository.repos["devops-bootcamp"]` et `["devops-bootcamp-gitops"]` ;
- `github_repository.repos` (`for_each` sur une `local`) : description, topics, squash merge uniquement, `delete_branch_on_merge`, `vulnerability_alerts`, **`prevent_destroy`** ;
- `github_branch_protection` sur `main` (pas de force push, pas de suppression) ;
- des labels communs aux deux repos grâce à **`setproduct()`**.

```bash
terraform init
terraform plan        # lis : "will be imported" + les modifications in-place
terraform apply
gh repo view tadeyayaoye/devops-bootcamp --json description,repositoryTopics
gh label list -R tadeyayaoye/devops-bootcamp-gitops
```

Teste les protections :

```bash
terraform plan -destroy            # prevent_destroy doit bloquer
gh api repos/tadeyayaoye/devops-bootcamp/branches/main/protection \
  | jq '{force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}'
```

Dérive : change la description d'un repo dans l'interface GitHub, puis `terraform plan`.

```bash
cd -
```

---

## Lab 4.6 — Qualité et sécurité du code IaC (≈ 15 min)

```bash
terraform fmt -recursive -check infra/terraform
for d in infra/terraform/{cluster,platform,github}; do terraform -chdir=$d validate; done
trivy config infra/terraform
```

Bonus : installe `tflint` (`curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash`) et passe-le sur chaque stack.

À partir de maintenant, ton cluster se (re)crée en deux commandes :

```bash
make tf-cluster && make tf-platform
```

---

## 🏁 Challenge (sans guide)

1. **Test natif** : écris `infra/terraform/modules/kind-cluster/tests/validation.tftest.hcl` qui vérifie (avec `command = plan` et `expect_failures`) que `worker_count = 9` est refusé. Lance `terraform test` depuis le module.
2. **Refactor** : dans la stack `platform`, renomme `module "platform"` en `module "base"` **sans rien détruire** (bloc `moved`).
3. **OpenTofu** : installe `tofu` (paquet officiel) et lance `tofu init && tofu plan` sur la stack `cluster` dans une copie du dossier. Que se passe-t-il avec le state existant ?

---

## ✅ Validation

```bash
make check-04
```
