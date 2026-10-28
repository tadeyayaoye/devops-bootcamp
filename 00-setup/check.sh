#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

title "Module 00 — Poste de travail"
check "Le repo est dans le système de fichiers Linux (pas /mnt/c)" bash -c '[[ "$(git rev-parse --show-toplevel)" != /mnt/* ]]'
hint "git clone dans ~ (cf. Lab 0.3)"
# PC du taff (8 Go physiques) : export MIN_WSL_RAM_GB=4 (cf. 00-setup/PC-TAFF.md)
export MIN_WSL_RAM_GB="${MIN_WSL_RAM_GB:-10}"
check "WSL dispose d'au moins ${MIN_WSL_RAM_GB} Go de RAM" bash -c '[[ $(free -g | awk "/Mem:/ {print \$2}") -ge $MIN_WSL_RAM_GB ]]'
hint ".wslconfig absent ou non pris en compte → wsl --shutdown (Lab 0.2)"
check "systemd est actif" bash -c 'systemctl is-system-running | grep -qE "running|degraded"'
check "vm.max_map_count >= 524288 (SonarQube)" bash -c '[[ $(sysctl -n vm.max_map_count) -ge 524288 ]]'
check "Docker répond sans sudo" docker info
hint "rouvre ton terminal après le bootstrap (groupe docker)"
for t in kubectl kind helm kustomize terraform ansible argocd kubeseal gh trivy hadolint gitleaks jq yq; do
  check "outil présent : $t" command -v "$t"
done

title "Git"
check "user.name configuré" git config user.name
check "user.email configuré" git config user.email
check "gh authentifié" gh auth status
check "Aucun CRLF dans les scripts" bash -c '! grep -rlI $'"'"'\r'"'"' "$ROOT/scripts"'

title "Application"
check "Le venv existe" test -x "$ROOT/app/.venv/bin/python"
hint "make app-venv"
check "Lint ruff OK" bash -c 'cd "$ROOT/app" && .venv/bin/ruff check .'
check "Tests pytest OK" bash -c 'cd "$ROOT/app" && .venv/bin/pytest -q'

summary
