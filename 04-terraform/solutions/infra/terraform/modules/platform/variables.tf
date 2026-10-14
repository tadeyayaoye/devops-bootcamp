variable "enable_argocd" {
  description = "Installer Argo CD et sa route"
  type        = bool
  default     = false
}

variable "chart_versions" {
  description = "Versions des charts (null = dernière)"
  type = object({
    metrics_server = optional(string)
    traefik        = optional(string)
    argocd         = optional(string)
  })
  default = {}
}
