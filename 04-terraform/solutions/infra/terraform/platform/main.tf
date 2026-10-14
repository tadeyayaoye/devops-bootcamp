# Stack 2/3 — la plateforme installée DANS le cluster : metrics-server, Traefik + Gateway, Argo CD.
terraform {
  required_version = ">= 1.6"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0" # v3 : syntaxe "kubernetes = { … }" et "set = [ … ]"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

module "platform" {
  source = "../modules/platform"

  enable_argocd  = var.enable_argocd
  chart_versions = var.chart_versions
}
