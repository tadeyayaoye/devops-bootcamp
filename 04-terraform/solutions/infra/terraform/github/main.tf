# Stack 3/3 — GitHub « as code » : réglages des repos, protection de branche, labels.
# Les deux repos existent déjà (créés à la main) → on les IMPORTE au lieu de les recréer.
#
#   export GITHUB_TOKEN=$(gh auth token)
#   terraform init && terraform plan
terraform {
  required_version = ">= 1.6"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = var.github_owner # le token est lu dans la variable d'environnement GITHUB_TOKEN
}

# --- Import déclaratif (Terraform >= 1.5) : visible dans le plan, revu en PR -------------
import {
  to = github_repository.repos["devops-bootcamp"]
  id = "devops-bootcamp"
}

import {
  to = github_repository.repos["devops-bootcamp-gitops"]
  id = "devops-bootcamp-gitops"
}

locals {
  repos = {
    "devops-bootcamp" = {
      description = "Mini-bootcamp DevOps local et gratuit : Docker, Kubernetes, Terraform, Ansible, Jenkins, SonarQube, Argo CD, Prometheus, Grafana, Loki, Tempo"
      topics      = ["devops", "kubernetes", "terraform", "ansible", "jenkins", "argocd", "prometheus", "grafana", "bootcamp"]
    }
    "devops-bootcamp-gitops" = {
      description = "Repo GitOps du bootcamp DevOps : état désiré du cluster, synchronisé par Argo CD"
      topics      = ["gitops", "argocd", "kustomize", "kubernetes"]
    }
  }

  labels = {
    "type: feature" = { color = "1d76db", description = "Nouvelle fonctionnalité" }
    "type: bug"     = { color = "d73a4a", description = "Quelque chose ne marche pas" }
    "infra"         = { color = "5319e7", description = "Terraform, Ansible, Kubernetes" }
    "ci"            = { color = "fbca04", description = "Pipelines Jenkins / GitHub Actions" }
    "promotion"     = { color = "0e8a16", description = "Promotion d'une version vers la prod" }
  }

  # produit cartésien repos × labels → une ressource par couple
  repo_labels = {
    for pair in setproduct(keys(local.repos), keys(local.labels)) :
    "${pair[0]}/${pair[1]}" => { repo = pair[0], label = pair[1] }
  }
}

resource "github_repository" "repos" {
  for_each = local.repos

  name        = each.key
  description = each.value.description
  topics      = each.value.topics
  visibility  = "public"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  # Historique propre : squash uniquement, branches supprimées après merge
  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true

  vulnerability_alerts = true

  lifecycle {
    prevent_destroy = true # un `terraform destroy` ne doit JAMAIS supprimer les repos
  }
}

resource "github_branch_protection" "main" {
  for_each = github_repository.repos

  repository_id = each.value.node_id
  pattern       = "main"

  allows_force_pushes = false
  allows_deletions    = false
  # Exiger une PR sur main du repo applicatif uniquement si demandé
  # (la CI pousse directement les mises à jour de tag sur le repo GitOps).
  dynamic "required_pull_request_reviews" {
    for_each = var.require_pull_request && each.key == "devops-bootcamp" ? [1] : []
    content {
      required_approving_review_count = 0
    }
  }
}

resource "github_issue_label" "labels" {
  for_each = local.repo_labels

  repository  = github_repository.repos[each.value.repo].name
  name        = each.value.label
  color       = local.labels[each.value.label].color
  description = local.labels[each.value.label].description
}
