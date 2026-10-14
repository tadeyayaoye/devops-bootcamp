#!/usr/bin/env bash
# Petite bibliothèque partagée par les scripts check.sh des modules.
# Usage : source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

PASS=0
FAIL=0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GITOPS_DIR="${GITOPS_DIR:-$ROOT/../devops-bootcamp-gitops}"
export ROOT GITOPS_DIR   # visibles dans les `bash -c '...'` des checks

title() { printf '\n\033[1;35m━━ %s ━━\033[0m\n' "$*"; }

# check "description" commande...  → exécute la commande, vert si code retour 0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32m✔\033[0m %s\n' "$desc"; PASS=$((PASS + 1)); LAST=0
  else
    printf '  \033[31m✘\033[0m %s\n' "$desc"; FAIL=$((FAIL + 1)); LAST=1
  fi
}

# hint "texte" → affiché seulement si le dernier check a échoué
LAST=0
hint() { [[ $LAST -eq 1 ]] && printf '    \033[33m↳ %s\033[0m\n' "$*"; return 0; }

summary() {
  echo
  if [[ $FAIL -eq 0 ]]; then
    printf '\033[1;32m🎉 %d/%d vérifications OK. Module validé !\033[0m\n' "$PASS" "$PASS"
  else
    printf '\033[1;31m%d OK, %d en échec.\033[0m Relis les labs concernés (ou compare avec solutions/).\n' "$PASS" "$FAIL"
    exit 1
  fi
}

# Helpers courants
http_ok() { curl -fsS --max-time 5 "$1" >/dev/null; }
k8s_ready() { kubectl -n "$1" rollout status "deploy/$2" --timeout=5s; }
file_has() { grep -qE "$2" "$1"; }
