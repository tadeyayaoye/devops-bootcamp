terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }
}

resource "kind_cluster" "this" {
  name           = var.name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # NodePort Traefik → ports de l'hôte (puis localhost Windows via WSL)
      extra_port_mappings {
        container_port = 30080
        host_port      = var.http_port
      }
      extra_port_mappings {
        container_port = 30443
        host_port      = var.https_port
      }
    }

    # Bloc dynamique : autant de nœuds worker que demandé
    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
