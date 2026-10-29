#!/usr/bin/env bash
# Vérifie la présence et la version de chaque outil du bootcamp.
set -uo pipefail

ok=0; ko=0
row() {
  local name="$1" cmd="$2" p
  # un binaire sous /mnt/c (ex. le docker de Docker Desktop) n'est pas un outil installé dans Ubuntu
  if p=$(command -v "$name" 2>/dev/null) && [[ $p != /mnt/* ]]; then
    printf '  \033[32m✔\033[0m %-14s %s\n' "$name" "$(eval "$cmd" 2>/dev/null | head -1)"
    ok=$((ok + 1))
  else
    printf '  \033[31m✘\033[0m %-14s absent\n' "$name"
    ko=$((ko + 1))
  fi
}

echo "Outils du bootcamp :"
row git        "git --version"
row docker     "docker version --format 'client {{.Client.Version}} / serveur {{.Server.Version}}'"
row kubectl    "kubectl version --client -o json | jq -r .clientVersion.gitVersion"
row kind       "kind version"
row helm       "helm version --short"
row kustomize  "kustomize version"
row k9s        "k9s version --short | head -1"
row terraform  "terraform version | head -1"
row ansible    "ansible --version | head -1"
row argocd     "argocd version --client --short"
row kubeseal   "kubeseal --version"
row gh         "gh --version | head -1"
row trivy      "trivy --version | head -1"
row hadolint   "hadolint --version"
row gitleaks   "gitleaks version"
row jq         "jq --version"
row yq         "yq --version"
row python3    "python3 --version"

echo
if docker info >/dev/null 2>&1; then
  echo "  Docker daemon : joignable ✔"
else
  echo "  Docker daemon : NON joignable ✘ (service démarré ? groupe docker ? → rouvre ton terminal)"
  ko=$((ko + 1))
fi
echo "  Mémoire WSL   : $(free -h | awk '/Mem:/ {print $2}') (attendu ≈ 12 Gi sur le PC perso, ≈ 5 Gi sur le PC du taff, cf .wslconfig)"
echo "  Répertoire    : $(pwd) $( [[ $(pwd) == /mnt/* ]] && echo '⚠ tu es sur le disque Windows : travaille dans ~ !')"
echo
[[ $ko -eq 0 ]] && echo "✅ Tout est prêt ($ok outils)." || { echo "❌ $ko problème(s). Relance ./scripts/bootstrap-wsl.sh"; exit 1; }
