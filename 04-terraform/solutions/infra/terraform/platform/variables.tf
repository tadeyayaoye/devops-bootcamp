variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-bootcamp"
}

variable "enable_argocd" {
  description = "Installer Argo CD (module 08)"
  type        = bool
  default     = false
}

variable "chart_versions" {
  description = "Versions épinglées des charts (null = dernière version : à éviter hors labo)"
  type = object({
    metrics_server = optional(string)
    traefik        = optional(string)
    argocd         = optional(string)
  })
  default = {}
}
