variable "name" {
  description = "Nom du cluster kind (le contexte kubectl sera kind-<name>)"
  type        = string
}

variable "worker_count" {
  description = "Nombre de nœuds worker"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 4
    error_message = "Entre 0 et 4 workers (16 Go de RAM…)."
  }
}

variable "node_image" {
  description = "Image kindest/node (version de Kubernetes). null = défaut de la version de kind."
  type        = string
  default     = null
}

variable "http_port" {
  description = "Port HTTP de l'hôte relié au NodePort 30080"
  type        = number
  default     = 80
}

variable "https_port" {
  description = "Port HTTPS de l'hôte relié au NodePort 30443"
  type        = number
  default     = 443
}
