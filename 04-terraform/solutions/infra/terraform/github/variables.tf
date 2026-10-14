variable "github_owner" {
  description = "Compte GitHub propriétaire des repos"
  type        = string
  default     = "tadeyayaoye"
}

variable "require_pull_request" {
  description = "Interdire le push direct sur main du repo devops-bootcamp (PR obligatoire)"
  type        = bool
  default     = false
}

output "repos" {
  value = { for k, r in github_repository.repos : k => r.html_url }
}
