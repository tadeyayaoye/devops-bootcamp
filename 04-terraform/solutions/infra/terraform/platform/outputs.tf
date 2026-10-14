output "releases" {
  description = "Releases Helm installées et leur version"
  value       = module.platform.releases
}

output "argocd_url" {
  value = var.enable_argocd ? "http://argocd.localhost" : "Argo CD non installé (enable_argocd = false)"
}
