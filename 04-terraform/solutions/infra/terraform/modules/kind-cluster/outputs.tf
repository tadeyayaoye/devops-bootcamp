output "name" {
  value = kind_cluster.this.name
}

output "kube_context" {
  description = "Contexte kubectl à utiliser"
  value       = "kind-${kind_cluster.this.name}"
}

output "endpoint" {
  description = "URL de l'API server"
  value       = kind_cluster.this.endpoint
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}
