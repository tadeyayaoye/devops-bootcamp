#!/usr/bin/env bash
# =============================================================================
# Installe tout l'outillage du bootcamp dans Ubuntu 24.04 (WSL2).
# Idempotent : tu peux le relancer autant de fois que tu veux.
#
#   ./scripts/bootstrap-wsl.sh
#
# Au module 05, tu réécriras une partie de ce script en rôle Ansible :
# compare les deux approches (impératif vs déclaratif).
# =============================================================================
set -euo pipefail

BIN=/usr/local/bin
ARCH=$(dpkg --print-architecture)          # amd64
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Trivy est épinglé volontairement : en mars 2026, les versions 0.69.4 à 0.69.6
# (binaires + images) et les tags de trivy-action ont été compromis (CVE-2026-33634).
# Vérifie la dernière version saine sur https://github.com/aquasecurity/trivy/releases
# avant de changer cette valeur.
TRIVY_VERSION="${TRIVY_VERSION:-0.69.3}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✔ %s\033[0m\n' "$*"; }
# Ignore les exécutables Windows visibles via le PATH (/mnt/c/...) : sinon le « docker » de
# Docker Desktop fait croire que Docker Engine est déjà installé dans Ubuntu.
have() { local p; p=$(command -v "$1" 2>/dev/null) && [[ $p != /mnt/* ]]; }
gh_latest() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name; }

if [[ $EUID -eq 0 ]]; then
  echo "Lance ce script avec ton utilisateur normal (pas root) : il utilisera sudo quand il le faut."
  exit 1
fi

# -----------------------------------------------------------------------------
log "Paquets de base (apt)"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg lsb-release apt-transport-https software-properties-common \
  git make jq unzip tar tree htop bash-completion \
  python3 python3-venv python3-pip pipx \
  openssh-client sshpass dnsutils iproute2 net-tools postgresql-client
ok "paquets de base"

# -----------------------------------------------------------------------------
log "Certificats d'entreprise (proxy HTTPS)"
# Sur un PC d'entreprise, le pare-feu (ex. Palo Alto) peut ré-signer les connexions HTTPS avec
# sa propre autorité : curl, apt et docker refusent alors ("self-signed certificate in
# certificate chain"). Windows fait confiance à cette autorité, Ubuntu non : on la lui copie.
#   CORP_CA_PATTERN=paloalto.aubay.com ./scripts/bootstrap-wsl.sh   (cf. 00-setup/PC-TAFF.md)
# Tu peux aussi déposer toi-même des certificats PEM (*.crt) dans ~/.bootcamp/ca/.
CA_DIR="$HOME/.bootcamp/ca"
if [[ -n "${CORP_CA_PATTERN:-}" ]]; then
  mkdir -p "$CA_DIR"
  rm -f "$CA_DIR"/corp-ca-*.crt
  powershell.exe -NoProfile -Command "Get-ChildItem Cert:\\LocalMachine\\Root | Where-Object Subject -match '${CORP_CA_PATTERN}' | ForEach-Object { '-----BEGIN CERTIFICATE-----'; [Convert]::ToBase64String(\$_.RawData, 'InsertLineBreaks'); '-----END CERTIFICATE-----' }" \
    | tr -d '\r' | awk -v d="$CA_DIR" '/BEGIN CERT/ {n++; f = sprintf("%s/corp-ca-%d.crt", d, n)} f {print > f}'
  compgen -G "$CA_DIR/corp-ca-*.crt" >/dev/null || { echo "Aucun certificat Windows ne correspond à '$CORP_CA_PATTERN'."; exit 1; }
fi
if compgen -G "$CA_DIR/*.crt" >/dev/null; then
  sudo install -d /usr/local/share/ca-certificates/bootcamp
  sudo install -m 0644 "$CA_DIR"/*.crt /usr/local/share/ca-certificates/bootcamp/
  sudo update-ca-certificates >/dev/null
  # pip (donc pipx/ansible) a son propre magasin de certificats : on lui donne celui du système
  export PIP_CERT=/etc/ssl/certs/ca-certificates.crt REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
  # dockerd ne relit les certificats qu'au démarrage
  systemctl is-active --quiet docker 2>/dev/null && sudo systemctl restart docker
  ok "certificats ajoutés : $(ls "$CA_DIR"/*.crt | xargs -n1 basename | tr '\n' ' ')"
else
  ok "aucun certificat d'entreprise (normal sur un PC perso)"
fi
# Contrôle avant d'aller plus loin : sans le bon certificat, gh/kubectl/helm/terraform échoueraient
# plus bas avec un message moins clair. curl renvoie 60 quand le certificat n'est pas reconnu.
rc=0; curl -fsS -o /dev/null -m 20 https://raw.githubusercontent.com/helm/helm/main/README.md || rc=$?
if [[ $rc -eq 60 ]]; then
  echo "    ✘ Un proxy d'entreprise intercepte le HTTPS et Ubuntu ne connaît pas son certificat."
  echo "      Relance avec :  CORP_CA_PATTERN=paloalto.aubay.com ./scripts/bootstrap-wsl.sh   (cf. 00-setup/PC-TAFF.md)"
  exit 1
fi

# -----------------------------------------------------------------------------
log "Réglages noyau (sysctl) pour kind multi-nœuds et SonarQube"
# - inotify : kind avec plusieurs nœuds épuise vite les watchers par défaut ("too many open files")
# - vm.max_map_count : Elasticsearch embarqué dans SonarQube l'exige
sudo tee /etc/sysctl.d/99-bootcamp.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
vm.max_map_count = 524288
EOF
sudo sysctl --system >/dev/null
ok "sysctl appliqués"

# -----------------------------------------------------------------------------
log "Docker Engine (dépôt officiel Docker, pas Docker Desktop)"
if ! have docker; then
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker >/dev/null 2>&1 || echo "    ⚠ systemd absent ? Vérifie /etc/wsl.conf ([boot] systemd=true) puis 'wsl --shutdown'."
ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"

# -----------------------------------------------------------------------------
log "GitHub CLI (gh)"
if ! have gh; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
fi
ok "gh $(gh --version | head -1 | awk '{print $3}')"

# -----------------------------------------------------------------------------
log "kubectl (dernière version stable, avec vérification du checksum)"
if ! have kubectl; then
  v=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo "$TMP/kubectl" "https://dl.k8s.io/release/${v}/bin/linux/${ARCH}/kubectl"
  curl -fsSLo "$TMP/kubectl.sha256" "https://dl.k8s.io/release/${v}/bin/linux/${ARCH}/kubectl.sha256"
  echo "$(cat "$TMP/kubectl.sha256")  $TMP/kubectl" | sha256sum --check --quiet
  sudo install -m 0755 "$TMP/kubectl" "$BIN/kubectl"
fi
ok "kubectl $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)"

# -----------------------------------------------------------------------------
log "kind"
if ! have kind; then
  curl -fsSLo "$TMP/kind" "https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-${ARCH}"
  curl -fsSLo "$TMP/kind.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-${ARCH}.sha256sum"
  (cd "$TMP" && sed "s#\S*kind-linux-${ARCH}#kind#" kind.sha256sum | sha256sum --check --quiet)
  sudo install -m 0755 "$TMP/kind" "$BIN/kind"
fi
ok "$(kind version)"

# -----------------------------------------------------------------------------
log "Helm 4"
if ! have helm; then
  curl -fsSL -o "$TMP/get-helm-4" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
  bash "$TMP/get-helm-4"
fi
ok "helm $(helm version --short)"

# -----------------------------------------------------------------------------
log "kustomize (standalone, pour 'kustomize edit set image')"
if ! have kustomize; then
  (cd "$TMP" && curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash >/dev/null)
  sudo install -m 0755 "$TMP/kustomize" "$BIN/kustomize"
fi
ok "kustomize $(kustomize version)"

# -----------------------------------------------------------------------------
log "Terraform (dépôt apt HashiCorp)"
if ! have terraform; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y terraform
fi
ok "$(terraform version | head -1)"

# -----------------------------------------------------------------------------
log "Ansible + ansible-lint (via pipx : isolés dans leur propre venv)"
pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"
have ansible        || pipx install --include-deps ansible
have ansible-lint   || pipx install ansible-lint
ok "$(ansible --version | head -1)"

# -----------------------------------------------------------------------------
log "Argo CD CLI"
if ! have argocd; then
  curl -fsSLo "$TMP/argocd" "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${ARCH}"
  sudo install -m 0755 "$TMP/argocd" "$BIN/argocd"
fi
ok "argocd $(argocd version --client --short 2>/dev/null | head -1)"

# -----------------------------------------------------------------------------
log "kubeseal (Sealed Secrets)"
if ! have kubeseal; then
  v=$(gh_latest bitnami-labs/sealed-secrets)
  curl -fsSLo "$TMP/kubeseal.tgz" "https://github.com/bitnami-labs/sealed-secrets/releases/download/${v}/kubeseal-${v#v}-linux-${ARCH}.tar.gz"
  tar -xzf "$TMP/kubeseal.tgz" -C "$TMP" kubeseal
  sudo install -m 0755 "$TMP/kubeseal" "$BIN/kubeseal"
fi
ok "kubeseal $(kubeseal --version 2>&1 | awk '{print $NF}')"

# -----------------------------------------------------------------------------
log "k9s, yq"
if ! have k9s; then
  curl -fsSLo "$TMP/k9s.tgz" "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${ARCH}.tar.gz"
  tar -xzf "$TMP/k9s.tgz" -C "$TMP" k9s
  sudo install -m 0755 "$TMP/k9s" "$BIN/k9s"
fi
if ! have yq; then
  curl -fsSLo "$TMP/yq" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}"
  sudo install -m 0755 "$TMP/yq" "$BIN/yq"
fi
ok "k9s + yq"

# -----------------------------------------------------------------------------
log "Outils DevSecOps : trivy ${TRIVY_VERSION} (épinglé), hadolint, gitleaks"
if ! have trivy; then
  deb="trivy_${TRIVY_VERSION}_Linux-64bit.deb"
  base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
  curl -fsSLo "$TMP/$deb" "$base/$deb"
  curl -fsSLo "$TMP/checksums.txt" "$base/trivy_${TRIVY_VERSION}_checksums.txt"
  (cd "$TMP" && grep " ${deb}\$" checksums.txt | sha256sum --check --quiet)
  sudo dpkg -i "$TMP/$deb" >/dev/null
fi
if ! have hadolint; then
  curl -fsSLo "$TMP/hadolint" "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64" \
    || curl -fsSLo "$TMP/hadolint" "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-x86_64"
  sudo install -m 0755 "$TMP/hadolint" "$BIN/hadolint"
fi
if ! have gitleaks; then
  v=$(gh_latest gitleaks/gitleaks)
  curl -fsSLo "$TMP/gitleaks.tgz" "https://github.com/gitleaks/gitleaks/releases/download/${v}/gitleaks_${v#v}_linux_x64.tar.gz"
  tar -xzf "$TMP/gitleaks.tgz" -C "$TMP" gitleaks
  sudo install -m 0755 "$TMP/gitleaks" "$BIN/gitleaks"
fi
ok "trivy $(trivy --version | head -1 | awk '{print $2}'), hadolint, gitleaks"

# -----------------------------------------------------------------------------
log "Confort shell (~/.bashrc) : alias + autocomplétion"
marker="# >>> devops-bootcamp >>>"
if ! grep -q "$marker" ~/.bashrc; then
  cat >> ~/.bashrc <<'EOF'
# >>> devops-bootcamp >>>
export PATH="$HOME/.local/bin:$PATH"
alias k=kubectl
alias kns='kubectl config set-context --current --namespace'
alias tf=terraform
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
source <(helm completion bash)
source <(kind completion bash)
complete -C "$(command -v terraform)" terraform tf
export DOCKER_BUILDKIT=1
# <<< devops-bootcamp <<<
EOF
fi
ok "~/.bashrc"

cat <<'EOF'

==========================================================================
 ✅ Installation terminée.

 ⚠ IMPORTANT : pour que l'appartenance au groupe 'docker' soit prise en
   compte, ferme ce terminal et rouvre-le (ou : `newgrp docker`).

 Ensuite :  make tools
==========================================================================
EOF
