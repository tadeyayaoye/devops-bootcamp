# Stack 1/3 — le cluster. Séparé de la plateforme : un provider (helm, kubernetes) ne doit pas
# dépendre d'une ressource créée dans la même stack (sa config serait inconnue au moment du plan).
terraform {
  required_version = ">= 1.6"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }

  # State local : suffisant pour un poste perso. En équipe → backend distant avec verrouillage :
  # backend "s3" { bucket = "…" key = "kind/cluster.tfstate" region = "…" use_lockfile = true }
}

module "cluster" {
  source = "../modules/kind-cluster"

  name         = var.cluster_name
  worker_count = var.worker_count
}

variable "cluster_name" {
  type    = string
  default = "bootcamp"
}

variable "worker_count" {
  type    = number
  default = 2
}

output "kube_context" {
  value = module.cluster.kube_context
}

output "endpoint" {
  value = module.cluster.endpoint
}
