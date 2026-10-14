# syntax=docker/dockerfile:1
# Jenkins « as code » : image + plugins + configuration (JCasC) versionnés, aucun clic.
FROM jenkins/jenkins:lts-jdk21

USER root
ARG KUSTOMIZE_VERSION=5.6.0

# CLI Docker (le démon reste celui de l'hôte, via le socket monté) + outils du pipeline
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg jq \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin kustomize

USER jenkins

# Plugins installés au build de l'image (reproductible, pas d'install manuelle dans l'UI)
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
