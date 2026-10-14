# Module 04 — Quiz Terraform

<details><summary>1. Qu'est-ce que le state Terraform et pourquoi est-il critique ?</summary>

Le fichier qui associe chaque adresse de ressource du code à l'objet réel (ID) et à ses attributs. Sans lui, Terraform ne sait pas ce qu'il gère (il voudrait tout recréer). Il contient souvent des secrets en clair, doit être partagé en équipe (backend distant), verrouillé pendant les opérations (locking), sauvegardé/versionné, et jamais commité dans Git.
</details>

<details><summary>2. Comment fonctionne le verrouillage du state et pourquoi en a-t-on besoin ?</summary>

Avant un plan/apply, Terraform pose un verrou sur le backend (fichier `.tflock` sur S3 avec `use_lockfile`, table DynamoDB historiquement, verrou natif GCS/azurerm/HCP). Deux applies simultanés sur le même state produiraient des écritures concurrentes, donc un state corrompu ou incohérent avec la réalité. `force-unlock` seulement si on est sûr qu'aucune opération ne tourne.
</details>

<details><summary>3. <code>count</code> ou <code>for_each</code> ?</summary>

`for_each` dès qu'on itère sur une collection d'objets distincts : les adresses sont indexées par clé (`["dev"]`) et restent stables quand on ajoute/retire un élément. `count` indexe par position : retirer un élément au milieu décale tous les suivants et provoque destructions/recréations. `count` reste idiomatique pour un toggle `cond ? 1 : 0`.
</details>

<details><summary>4. Que signifie <code>-/+</code> dans un plan et pourquoi faut-il s'en méfier ?</summary>

Remplacement : la ressource va être détruite puis recréée (ou l'inverse avec `create_before_destroy`) car un attribut immuable change (« forces replacement »). Pour une base de données, un disque ou un cluster, c'est une perte de données ou une coupure. On le détecte en lisant le plan, et on se protège avec `prevent_destroy`, des politiques en CI, ou en revoyant la modification.
</details>

<details><summary>5. Une ressource existe déjà (créée à la main). Comment la faire gérer par Terraform ?</summary>

L'importer : bloc `import { to = …, id = … }` (Terraform ≥ 1.5), visible dans le plan et revu en PR ; ou la commande `terraform import` (impérative). Ensuite écrire/ajuster la configuration jusqu'à ce que le plan n'affiche plus de changement (`terraform plan -generate-config-out=` peut générer un brouillon de HCL).
</details>

<details><summary>6. Comment renommer une ressource ou la déplacer dans un module sans la recréer ?</summary>

Bloc `moved { from = … to = … }` : Terraform met à jour l'adresse dans le state lors du prochain apply, sans toucher à l'infra. Alternative impérative : `terraform state mv`. Pour arrêter de gérer une ressource sans la détruire : bloc `removed` (lifecycle destroy = false) ou `terraform state rm`.
</details>

<details><summary>7. Qu'est-ce que la dérive (drift) et comment la gérer ?</summary>

Un écart entre la réalité et le code/state, causé par une modification manuelle ou un autre outil. `terraform plan` (ou `plan -refresh-only`) la montre ; on la corrige en réappliquant le code, ou on intègre le changement dans le code s'il était voulu. On la détecte par des plans planifiés en CI. `ignore_changes` pour les attributs gérés volontairement ailleurs.
</details>

<details><summary>8. Pourquoi séparer le code en plusieurs stacks/states (cluster, plateforme, GitHub) ?</summary>

Réduire le *blast radius* (une erreur ne touche qu'un périmètre), accélérer les plans, séparer les droits et les cycles de vie (le réseau change rarement, les applis souvent), et éviter qu'un provider dépende d'une ressource créée dans le même apply (configuration inconnue au plan). Les stacks communiquent par outputs/`terraform_remote_state`/data sources ou par conventions (nom du contexte kubectl).
</details>

<details><summary>9. Que contient <code>.terraform.lock.hcl</code> et faut-il le commiter ?</summary>

Les versions exactes des providers sélectionnées par `init` et leurs hash de vérification. Oui, on le commite : tous les membres et la CI utilisent exactement les mêmes binaires de providers (reproductibilité, protection supply chain). On le met à jour volontairement avec `terraform init -upgrade`.
</details>

<details><summary>10. Workspaces ou un dossier par environnement ?</summary>

Les workspaces donnent plusieurs states pour un même code : pratique pour des copies strictement identiques, mais les différences entre envs finissent en conditions `terraform.workspace == "prod"` et le risque d'appliquer sur le mauvais workspace est réel. Un dossier par environnement appelant des modules communs rend les différences explicites et les states/backends/droits séparés : approche la plus courante.
</details>

<details><summary>11. <code>sensitive = true</code> protège-t-il un secret ?</summary>

Il le masque seulement dans la sortie CLI/les logs de plan. La valeur reste en clair dans le state (et dans le plan sauvegardé). Il faut protéger le state (backend chiffré, accès restreint), préférer des secrets générés/stockés dans un gestionnaire (Vault, cloud secret manager) et référencés, et OpenTofu propose le chiffrement du state côté client.
</details>

<details><summary>12. Terraform vs Ansible ?</summary>

Terraform provisionne des ressources via des API, de façon déclarative avec un state : réseaux, VM, clusters, DNS, comptes, repos. Ansible configure l'intérieur de machines existantes (paquets, fichiers, services) via SSH, sans state, avec des modules idempotents exécutés dans l'ordre. Ils sont complémentaires : Terraform crée la VM, Ansible (ou cloud-init, ou une image Packer) la configure.
</details>

<details><summary>13. Terraform et OpenTofu : quelle différence ?</summary>

OpenTofu est le fork open source (MPL, Linux Foundation) de Terraform créé après le passage de Terraform sous licence BSL en 2023. Même langage HCL et compatibilité des providers et du state (au moins jusqu'aux versions communes), avec des fonctionnalités propres à chacun depuis (chiffrement du state, for_each sur providers côté OpenTofu ; fonctions/stack côté Terraform/HCP).
</details>

<details><summary>14. Pourquoi ne gère-t-on pas toutes les applications Kubernetes avec Terraform ?</summary>

Terraform n'agit qu'au moment de l'apply (pas de réconciliation continue), les states deviennent énormes et lents, les CRD doivent exister au plan (`kubernetes_manifest`), et les équipes applicatives n'ont pas à toucher au state de la plateforme. Pattern courant : Terraform pour le socle (cluster, réseau, IAM, Argo CD), GitOps (Argo CD/Flux) pour les applications.
</details>

<details><summary>15. Décris un pipeline CI/CD pour du code Terraform.</summary>

Sur PR : fmt -check, validate, tflint, scan sécurité (trivy/checkov), `plan` dont le résultat est posté en commentaire. Revue humaine du plan. Au merge : `apply` du plan revu (ou re-plan + apply), avec verrouillage, identité OIDC à privilèges minimaux, approbation manuelle pour la prod (environnement protégé). Détection de dérive planifiée. Outils : Atlantis, HCP Terraform, Spacelift, GitHub Actions/GitLab CI.
</details>
