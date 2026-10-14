# Module 04 — Infrastructure as Code avec Terraform

> **Objectif** : comprendre le modèle de Terraform (graphe, state, providers), écrire du HCL propre et modulaire, maîtriser le cycle de vie (plan, import, refactor, drift), et l'utiliser pour créer **ton cluster, ta plateforme et tes repos GitHub**.
>
> **Durée** : cours ~1 h 45 · labs ~3 h · quiz 30 min

---

## 1. Pourquoi l'Infrastructure as Code

| Sans IaC (« ClickOps ») | Avec IaC |
|---|---|
| Configuration dans la tête des gens / des wikis périmés | L'infra **est** le code, versionné dans Git |
| Environnements qui divergent (« ça marche en recette ») | Environnements reproductibles à l'identique |
| Changements non revus | Revue en PR, `plan` lisible avant chaque changement |
| Reconstruction après sinistre = semaines | `terraform apply` |
| Aucune traçabilité | Historique Git = journal d'audit |

### Déclaratif vs impératif

- **Impératif** (script bash, `aws cli`) : *comment* faire, étape par étape. Relancer le script = créer des doublons.
- **Déclaratif** (Terraform, Kubernetes, Ansible dans une large mesure) : *quoi* obtenir. L'outil calcule le chemin depuis l'état actuel → **idempotence**.

### Le paysage

| Outil | Rôle principal |
|---|---|
| **Terraform / OpenTofu** | **provisionner** des ressources via des API (cloud, SaaS, Kubernetes, GitHub…) |
| Pulumi | même rôle, en vrais langages (TS, Python, Go) |
| CloudFormation / Bicep | IaC native AWS / Azure |
| Crossplane | IaC pilotée par Kubernetes (CRD + réconciliation continue) |
| **Ansible** | **configurer** des machines existantes (paquets, fichiers, services) → module 05 |

> 💡 Terraform (avec Packer pour les images) pose les fondations ; Ansible configure l'intérieur des machines ; Kubernetes + GitOps gèrent les applications.

### Terraform vs OpenTofu

En 2023, HashiCorp a changé la licence de Terraform (MPL → **BSL**) : usage libre, mais interdit de bâtir un produit concurrent. La communauté a forké la dernière version MPL : **OpenTofu** (Linux Foundation). Le HCL est compatible, les providers aussi (registre propre). OpenTofu a ajouté des fonctions (chiffrement du state, `for_each` sur les providers…). Pour toi : **le code de ce module fonctionne avec les deux** (`tofu init/plan/apply`). Savoir l'expliquer en entretien est attendu.

---

## 2. Comment Terraform fonctionne

```
   fichiers .tf  ──┐
                   ├─► Terraform Core ──► graphe de dépendances ──► plan (diff)
   state (.tfstate)┘         │                                          │
                             │ gRPC (plugin protocol)                    ▼
                    ┌────────┴─────────┐                              apply
                    │ Providers        │ ──► API (kind/Docker, Helm, Kubernetes, GitHub, AWS…)
                    └──────────────────┘
```

1. **Core** lit la configuration, construit un **graphe** de ressources (dépendances implicites par références `resource.x.attr`, explicites par `depends_on`), et parallélise ce qui peut l'être (10 en parallèle par défaut).
2. **Providers** : plugins (un binaire par provider) qui traduisent les ressources en appels d'API. Téléchargés par `terraform init` depuis le registre, versions verrouillées dans **`.terraform.lock.hcl`** (à commiter).
3. **State** : la mémoire de Terraform (voir § 4).
4. **Refresh → diff → plan → apply** : Terraform lit l'état réel, le compare à la config, calcule les actions (`+` create, `~` update in-place, `-/+` replace, `-` destroy).

> ⚠ `-/+` (replace) = **destruction puis recréation**. Sur une base de données, c'est une perte de données. On lit **toujours** le plan, en particulier les lignes `# forces replacement`.

---

## 3. HCL, l'essentiel

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 3.0" }   # ~> 3.0 = >= 3.0, < 4.0
  }
  backend "s3" { … }                     # où stocker le state
}

provider "helm" { kubernetes = { config_path = "~/.kube/config" } }

variable "env" {                          # entrée
  type        = string
  description = "Environnement"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env doit valoir dev ou prod."
  }
}

locals {                                  # valeurs calculées, pour éviter la répétition
  name = "taskapi-${var.env}"
}

data "github_user" "me" { username = "" } # LECTURE d'une ressource existante

resource "helm_release" "traefik" { … }   # ressource GÉRÉE

module "cluster" { source = "./modules/kind-cluster" … }   # réutilisation

output "url" { value = "http://${local.name}.localhost" }  # sortie
```

### Types et expressions

- Types : `string`, `number`, `bool`, `list(T)`, `set(T)`, `map(T)`, `object({…})` (avec `optional(type, défaut)`), `tuple`, `any`.
- Interpolation `"${…}"`, conditionnelle `cond ? a : b`, `for` : `[for s in var.list : upper(s)]`, `{for k, v in var.map : k => v.port}`, splat `aws_instance.web[*].id`.
- Fonctions utiles : `templatefile`, `file`, `yamlencode/jsondecode`, `merge`, `lookup`, `coalesce`, `try`, `can`, `setproduct`, `flatten`, `cidrsubnet`, `pathexpand`.
- **`sensitive = true`** masque une valeur dans l'affichage, **pas dans le state**.

### Ordre de priorité des variables (du plus faible au plus fort)

défaut dans `variable` → `TF_VAR_nom` (env) → `terraform.tfvars` → `*.auto.tfvars` → `-var-file` → `-var` en ligne de commande.

### Méta-arguments

| Méta-argument | Usage |
|---|---|
| `count` | N copies indexées `[0]`, `[1]`… Pour des toggles : `count = var.enabled ? 1 : 0` |
| `for_each` | une copie par clé d'une map/set → **adresses stables** (`["dev"]`) ✅ |
| `depends_on` | dépendance que Terraform ne peut pas déduire (ex. CRD installées par un autre chart) |
| `provider` | choisir un provider aliasé (multi-région, multi-cluster) |
| `lifecycle` | `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by`, `precondition/postcondition` |

> ⚠ **`count` sur une liste** : retirer l'élément du milieu décale les index → Terraform détruit/recrée tout ce qui suit. Utilise `for_each` avec des clés stables.

Les blocs **`dynamic`** génèrent des blocs imbriqués répétés (ex. un bloc `node` par worker kind).

---

## 4. Le state : le point le plus important

Le fichier `terraform.tfstate` (JSON) associe chaque **adresse** (`module.cluster.kind_cluster.this`) à l'**ID réel** de la ressource et à ses attributs connus.

Pourquoi c'est critique :
- **Sans state, Terraform ne sait pas ce qu'il gère** → il essaierait de tout recréer.
- Il contient des **secrets en clair** (mots de passe générés, kubeconfigs, tokens) → ne JAMAIS le commiter, le chiffrer au repos, restreindre son accès.
- Deux `apply` simultanés sur le même state = corruption → il faut du **verrouillage (locking)**.

### Backends

| Backend | Verrouillage |
|---|---|
| `local` (défaut) | fichier local, verrou local — OK seul·e |
| `s3` | `use_lockfile = true` (verrou natif S3 ; DynamoDB n'est plus nécessaire) |
| `gcs`, `azurerm` | natif |
| HCP Terraform / Terraform Enterprise, Spacelift, env0, Scalr | SaaS : state, locks, runs, politiques |
| `pg`, `kubernetes`, `http` | divers |

### Commandes de state

```bash
terraform state list                         # adresses gérées
terraform state show 'module.cluster.kind_cluster.this'
terraform state mv  a.b c.d                  # renommer (préférer le bloc moved)
terraform state rm  a.b                      # oublier sans détruire (préférer le bloc removed)
terraform import    a.b <id>                 # adopter une ressource existante (préférer le bloc import)
terraform plan -refresh-only                 # voir la DÉRIVE entre state et réalité
terraform force-unlock <id>                  # en dernier recours
```

### Refactoring déclaratif (à connaître !)

```hcl
import {                       # adopter une ressource existante (TF ≥ 1.5)
  to = github_repository.repos["devops-bootcamp"]
  id = "devops-bootcamp"
}

moved {                        # renommer/déplacer sans détruire (TF ≥ 1.1)
  from = helm_release.traefik
  to   = module.platform.helm_release.traefik
}

removed {                      # arrêter de gérer sans détruire (TF ≥ 1.7)
  from = github_issue_label.old
  lifecycle { destroy = false }
}
```

Ces blocs passent dans le `plan` et en revue de code, contrairement aux commandes `state …` exécutées à la main. `terraform plan -generate-config-out=generated.tf` génère même le HCL d'une ressource importée.

### Drift (dérive)

Quelqu'un modifie une ressource à la main (console, `kubectl edit`…) : au prochain `plan`, Terraform propose de **remettre la config du code**. Détecter la dérive régulièrement (plan planifié en CI) est une bonne pratique ; `ignore_changes` sert pour les attributs volontairement gérés ailleurs (ex. `replicas` piloté par un HPA).

---

## 5. Modules

Un module = un dossier de `.tf` avec des **variables** (entrées) et des **outputs** (sorties). Le dossier courant est le *root module*.

```
infra/terraform/
├── modules/
│   ├── kind-cluster/     main.tf · variables.tf · outputs.tf   (réutilisable)
│   └── platform/         main.tf · variables.tf · outputs.tf · values/ · charts/
├── cluster/              stack 1 : appelle modules/kind-cluster   → son propre state
├── platform/             stack 2 : appelle modules/platform       → son propre state
└── github/               stack 3 : repos, protections, labels     → son propre state
```

Bonnes pratiques :
- Interface claire : variables **typées, décrites, validées** ; outputs utiles.
- Pas de bloc `provider` dans un module réutilisable (il hérite de l'appelant).
- Versionner les modules (tag Git `?ref=v1.2.0`, registre privé).
- **Découper le state** par cycle de vie et par périmètre (réseau / cluster / plateforme / applis ; un state par environnement) : *blast radius* réduit, plans plus rapides, droits séparés.
- Ne pas configurer un provider avec les sorties d'une ressource de la **même** stack (ex. provider helm qui dépend du cluster créé dans le même apply) → c'est pour ça qu'on a deux stacks `cluster` et `platform`.

### Plusieurs environnements

| Approche | Principe | Avis |
|---|---|---|
| **Un dossier par env** (`envs/dev`, `envs/prod`) appelant les mêmes modules | states séparés, différences explicites | ✅ le plus courant et lisible |
| `terraform workspace` | plusieurs states pour le même code | pratique pour des copies identiques, piégeux sinon (on applique sur le mauvais workspace) |
| Terragrunt | surcouche DRY (backends, dépendances entre stacks) | populaire dans les grosses organisations |

---

## 6. Workflow et qualité

```bash
terraform fmt -recursive        # formatage canonique
terraform validate              # syntaxe + cohérence des types
tflint                          # bonnes pratiques, erreurs propres aux providers
trivy config . / checkov -d .   # sécurité (bucket public, SG 0.0.0.0/0…)
terraform test                  # tests natifs (.tftest.hcl)
terraform plan -out=tfplan      # plan figé…
terraform apply tfplan          # …appliqué tel quel (ce qui a été revu = ce qui est appliqué)
```

**En équipe (CI/CD de l'IaC)** : PR → `fmt`/`validate`/`tflint`/scan → `plan` posté en commentaire de PR → revue → merge → `apply` du plan (Atlantis, HCP Terraform, GitHub Actions, Spacelift…). Identifiants cloud via **OIDC** (pas de clés longues durées), droits minimaux, politiques (*policy as code* : OPA/Conftest, Sentinel).

À éviter : `-target` en routine (contourne le graphe), `apply -auto-approve` sur la prod à la main, éditer le state à la main, `local-exec` partout (impératif déguisé).

---

## 7. Les providers utilisés ici

| Provider | Ressources | Remarque |
|---|---|---|
| `tehcyx/kind` | `kind_cluster` | crée un cluster kind (ne sait pas le modifier : tout changement = recréation) |
| `hashicorp/helm` **v3** | `helm_release` | syntaxe v3 : `kubernetes = { … }` (attribut objet), `set = [ { name, value } ]` (liste) au lieu de blocs |
| `hashicorp/kubernetes` | `kubernetes_namespace_v1`, `kubernetes_manifest`… | `kubernetes_manifest` exige que les CRD existent **au moment du plan** |
| `integrations/github` | `github_repository`, `github_branch_protection`, `github_issue_label`, `github_actions_secret`… | token via `GITHUB_TOKEN` |

> Gérer des **applications** Kubernetes avec Terraform est possible mais déconseillé à grande échelle (state énorme, pas de réconciliation continue) : Terraform installe le **socle** (cluster, Argo CD), puis **GitOps** prend le relais pour les applis (module 08). C'est le pattern le plus répandu.

---

## Pièges classiques

- State commité dans Git (secrets !) ou perdu (Terraform veut tout recréer).
- `count` sur des listes → recréations en cascade.
- Versions de providers non contraintes → un `init -upgrade` casse tout (ex. Helm provider 2 → 3 : syntaxe incompatible).
- Ressource modifiée à la main → drift, puis écrasée au prochain apply.
- Supprimer une ressource du code = la **détruire** au prochain apply (utiliser `removed` si on veut juste arrêter de la gérer).
- Secrets dans les variables par défaut ou dans les `.tfvars` commités.
- Dépendances implicites manquantes (CRD) → `depends_on`.

---

## Pour aller plus loin

- [Terraform tutorials (HashiCorp)](https://developer.hashicorp.com/terraform/tutorials)
- [OpenTofu docs](https://opentofu.org/docs/)
- [Terraform best practices (Anton Babenko)](https://www.terraform-best-practices.com/)
- [Google Cloud — Terraform best practices](https://cloud.google.com/docs/terraform/best-practices/general-style-structure)
