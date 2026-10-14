# Module "platform" : tout ce qui doit exister dans le cluster AVANT les applications.
# Les providers helm et kubernetes sont hérités de la stack appelante.
terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

locals {
  namespaces = merge(
    {
      traefik    = { "app.kubernetes.io/part-of" = "platform" }
      monitoring = { "app.kubernetes.io/part-of" = "platform" } # utilisé aux modules 09-10
    },
    var.enable_argocd ? { argocd = { "app.kubernetes.io/part-of" = "platform" } } : {}
  )
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name   = each.key
    labels = each.value
  }
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_versions.metrics_server
  namespace  = "kube-system"
  values     = [file("${path.module}/values/metrics-server.yaml")]
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.chart_versions.traefik
  namespace  = kubernetes_namespace_v1.this["traefik"].metadata[0].name
  values     = [file("${path.module}/values/traefik.yaml")]
  wait       = true
}

# Chart LOCAL : GatewayClass + Gateway. Il dépend des CRD Gateway API installées par Traefik,
# d'où le depends_on explicite (Terraform ne peut pas le deviner).
resource "helm_release" "gateway" {
  name       = "platform-gateway"
  chart      = "${path.module}/charts/gateway"
  namespace  = helm_release.traefik.namespace
  depends_on = [helm_release.traefik]
}

resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_versions.argocd
  namespace  = kubernetes_namespace_v1.this["argocd"].metadata[0].name
  values     = [file("${path.module}/values/argocd.yaml")]
  wait       = true
  timeout    = 600
}

# Routes HTTP des outils de plateforme (chart local générique)
resource "helm_release" "routes" {
  count = var.enable_argocd ? 1 : 0

  name      = "platform-routes"
  chart     = "${path.module}/charts/routes"
  namespace = helm_release.traefik.namespace

  values = [yamlencode({
    routes = [
      { name = "argocd", namespace = "argocd", hostname = "argocd.localhost", service = "argocd-server", port = 80 },
    ]
  })]

  depends_on = [helm_release.gateway, helm_release.argocd]
}
