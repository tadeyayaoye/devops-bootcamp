# Helm & Kustomize — fiche mémo

## Helm

```bash
helm repo add r https://… && helm repo update        helm search repo r/chart --versions | head
helm show values r/chart > defaults.yaml              helm show chart r/chart
helm upgrade --install rel r/chart -n ns --create-namespace -f values.yaml --version X.Y.Z --wait
helm list -A                                          helm status rel -n ns
helm get values rel -n ns [--all]                     helm get manifest rel -n ns
helm history rel -n ns                                helm rollback rel 2 -n ns
helm uninstall rel -n ns
helm template rel ./chart -f v.yaml                   helm lint ./chart
helm create mychart                                   helm test rel -n ns
helm package ./chart && helm push chart-0.1.0.tgz oci://ghcr.io/u/charts
```

Templates : `{{ .Values.x }}` · `{{ include "n.fullname" . }}` · `{{- toYaml .Values.r | nindent 12 }}` · `{{- if … }}{{- end }}` · `{{- range … }}` · `{{- with … }}` · `{{ required "msg" .Values.x }}` · `{{ default "d" .Values.x }}` · `{{ .Capabilities.APIVersions.Has "g/v1/Kind" }}` · checksum : `{{ include (print $.Template.BasePath "/cm.yaml") . | sha256sum }}`.

Helm 4 : `--rollback-on-failure` (ex `--atomic`), server-side apply par défaut pour les nouvelles releases, registres OCI natifs.

## Kustomize

```bash
kustomize build overlays/prod | less      kubectl apply -k overlays/prod       kubectl diff -k overlays/prod
cd overlays/dev && kustomize edit set image ghcr.io/u/app:1a2b3c4
kustomize edit add resource x.yaml        kustomize edit set namespace ns
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: app-prod
resources: [../../base, extra.yaml]
images: [{ name: ghcr.io/u/app, newTag: 1a2b3c4 }]
replicas: [{ name: app, count: 3 }]
labels: [{ pairs: { env: prod }, includeSelectors: false }]
configMapGenerator:
  - { name: app-config, behavior: merge, literals: [LOG_LEVEL=WARNING] }
secretGenerator: [ … ]                     # ⚠ pas de secrets en clair dans Git
patches:
  - path: patch-resources.yaml             # strategic merge
  - target: { kind: HTTPRoute, name: app }
    patch: |-
      - { op: replace, path: /spec/hostnames/0, value: app.example.com }
components: [../../components/tracing]
```
