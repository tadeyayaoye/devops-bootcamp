# Lab 4.1 — Bac à sable : apprendre HCL, le state et le cycle plan/apply sans aucun risque.
terraform {
  required_version = ">= 1.6"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "environments" {
  description = "Environnements à générer, avec leur nombre de réplicas"
  type = map(object({
    replicas = number
    debug    = optional(bool, false)
  }))
  default = {
    dev  = { replicas = 1, debug = true }
    prod = { replicas = 3 }
  }

  validation {
    condition     = alltrue([for e in values(var.environments) : e.replicas >= 1 && e.replicas <= 10])
    error_message = "replicas doit être compris entre 1 et 10."
  }
}

variable "owner" {
  type    = string
  default = "bootcamp"
}

locals {
  generated_dir = "${path.module}/generated"
  common_tags = {
    owner      = var.owner
    managed_by = "terraform"
  }
}

# Un mot de passe aléatoire par environnement (stocké dans le state : le state est SENSIBLE)
resource "random_password" "db" {
  for_each = var.environments
  length   = 20
  special  = false
}

resource "local_file" "config" {
  for_each = var.environments

  filename        = "${local.generated_dir}/${each.key}.env"
  file_permission = "0600"
  content = templatefile("${path.module}/config.env.tftpl", {
    env      = each.key
    replicas = each.value.replicas
    debug    = each.value.debug
    tags     = local.common_tags
  })
}

# Un fichier qui dépend de TOUS les autres → Terraform déduit l'ordre (graphe de dépendances)
resource "local_file" "index" {
  filename = "${local.generated_dir}/index.txt"
  content  = join("\n", [for env, f in local_file.config : "${env} → ${f.filename}"])
}

output "files" {
  description = "Fichiers générés"
  value       = { for env, f in local_file.config : env => f.filename }
}

output "db_passwords" {
  value     = { for env, p in random_password.db : env => p.result }
  sensitive = true # masqué dans la sortie… mais en clair dans terraform.tfstate !
}
