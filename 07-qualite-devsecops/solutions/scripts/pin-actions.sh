#!/usr/bin/env bash
# Épingle chaque action GitHub (uses: owner/repo@tag) sur le SHA de commit correspondant :
#   uses: actions/checkout@v5   →   uses: actions/checkout@<sha40> # v5
# Un tag peut être déplacé (c'est ainsi que trivy-action a été compromise en mars 2026) ; un SHA, non.
#
#   ./scripts/pin-actions.sh .github/workflows/ci.yml
set -euo pipefail

files=("$@")
[[ ${#files[@]} -eq 0 ]] && files=(.github/workflows/*.yml)

for wf in "${files[@]}"; do
  echo "== $wf"
  # lignes "uses: owner/repo[/chemin]@ref" pas encore épinglées (ref ≠ 40 caractères hexa)
  grep -oE 'uses: *[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[A-Za-z0-9_.-]+' "$wf" | sort -u | while read -r _ ref; do
    action="${ref%@*}"; version="${ref#*@}"
    [[ "$version" =~ ^[0-9a-f]{40}$ ]] && { echo "  déjà épinglé : $action"; continue; }
    repo=$(cut -d/ -f1-2 <<<"$action")
    sha=$(gh api "repos/$repo/commits/$version" --jq .sha)
    sed -i "s#uses: *${action}@${version}\$#uses: ${action}@${sha} \# ${version}#" "$wf"
    echo "  $action@$version → $sha"
  done
done
