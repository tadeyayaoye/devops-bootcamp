# Terraform — fiche mémo

```bash
terraform init [-upgrade]            terraform fmt -recursive [-check]     terraform validate
terraform plan [-out=tfplan] [-var 'k=v'] [-var-file=prod.tfvars] [-refresh-only] [-destroy]
terraform apply [tfplan] [-auto-approve]                                 terraform destroy
terraform output [-json] [nom]       terraform console                     terraform graph | dot -Tpng > g.png
terraform state list / show <addr> / mv <a> <b> / rm <addr> / pull
terraform import <addr> <id>         terraform plan -generate-config-out=gen.tf
terraform force-unlock <id>          terraform providers lock -platform=linux_amd64
terraform test                       terraform -chdir=infra/x plan
terraform workspace list/new/select  TF_LOG=DEBUG terraform plan
```

```hcl
variable "envs" {
  type = map(object({ replicas = number, debug = optional(bool, false) }))
  validation { condition = alltrue([for e in values(var.envs) : e.replicas > 0]) error_message = "…" }
}
locals { name = "app-${terraform.workspace}" }
resource "x" "y" {
  for_each = var.envs                         # each.key / each.value
  count    = var.enabled ? 1 : 0              # toggle
  depends_on = [helm_release.crds]
  lifecycle {
    prevent_destroy       = true
    create_before_destroy = true
    ignore_changes        = [tags]
    replace_triggered_by  = [terraform_data.v]
  }
  dynamic "node" { for_each = range(2) content { role = "worker" } }
}
import  { to = github_repository.r["a"]  id = "a" }
moved   { from = a.b  to = module.m.a.b }
removed { from = a.b  lifecycle { destroy = false } }
output "url" { value = "…"  sensitive = false }
```

Contraintes de version : `~> 3.0` (≥ 3.0, < 4.0) · `~> 3.2.1` (≥ 3.2.1, < 3.3) · `>= 1.6`.
Priorité des variables : défaut < `TF_VAR_x` < terraform.tfvars < *.auto.tfvars < -var-file < -var.
Helm provider v3 : `kubernetes = { … }` et `set = [ { name, value } ]`.
OpenTofu : mêmes commandes avec `tofu`.
