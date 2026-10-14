output "releases" {
  value = merge(
    {
      (helm_release.metrics_server.name) = helm_release.metrics_server.metadata.version
      (helm_release.traefik.name)        = helm_release.traefik.metadata.version
    },
    { for r in helm_release.argocd : r.name => r.metadata.version }
  )
}
