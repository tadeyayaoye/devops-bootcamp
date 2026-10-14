# Module 03 — Kubernetes avancé : exposition, état, scaling, sécurité, packaging

> **Objectif** : exposer proprement une appli (Gateway API), gérer des données (StatefulSet, PVC), scaler automatiquement, sécuriser (RBAC, Pod Security, NetworkPolicy), et packager avec **Helm** et **Kustomize** — les deux outils que tu croiseras partout.
>
> **Durée** : cours ~2 h · labs ~3 h 30 · quiz 30 min

---

## 1. Exposer du HTTP : d'Ingress à Gateway API

### 1.1 Rappel : Ingress

L'objet `Ingress` décrit des règles HTTP (host, path → Service), appliquées par un **Ingress Controller** (nginx, Traefik, HAProxy…). Limites : un seul objet mélange les responsabilités de l'équipe plateforme et des équipes applicatives, et toutes les fonctions avancées (réécriture, canary, timeouts…) passent par des **annotations non standard** propres à chaque contrôleur.

> 📰 **Actualité à connaître** : le projet **ingress-nginx** (le contrôleur communautaire le plus déployé au monde) a été **retiré en mars 2026** (plus de correctifs, y compris de sécurité). Les équipes migrent vers Gateway API (Envoy Gateway, Traefik, Cilium, Istio, NGINX Gateway Fabric…). Savoir l'expliquer est un vrai plus en entretien.

### 1.2 Gateway API : un modèle orienté rôles

```
  Fournisseur d'infra        Équipe plateforme             Équipes applicatives
 ┌──────────────────┐      ┌────────────────────┐        ┌───────────────────────┐
 │  GatewayClass    │◄─────│  Gateway           │◄───────│  HTTPRoute            │
 │  "traefik"       │      │  listeners: :80    │ parent │  host: taskapi.local… │
 │  (quel contrôleur)│     │  allowedRoutes: All│  Refs  │  path / → svc taskapi │
 └──────────────────┘      └────────────────────┘        └───────────────────────┘
```

- **GatewayClass** : type de passerelle (comme une StorageClass), géré par un contrôleur.
- **Gateway** : une instance (un point d'entrée, des *listeners* : port, protocole, TLS, hostnames autorisés, namespaces autorisés à s'y attacher).
- **HTTPRoute** (+ GRPCRoute, TLSRoute, TCPRoute…) : règles de routage portées par l'équipe de l'appli, dans **son** namespace.
- Fonctions **standard** sans annotations : matching sur headers/méthodes/query, réécriture d'URL, redirections, ajout de headers, **répartition pondérée** (canary : 90 % v1 / 10 % v2), mirroring, timeouts.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: taskapi, namespace: taskapi }
spec:
  parentRefs: [{ name: main, namespace: traefik }]
  hostnames: ["taskapi.localhost"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs:
        - { name: taskapi, port: 80, weight: 90 }
        - { name: taskapi-canary, port: 80, weight: 10 }
```

### 1.3 Notre montage local

```
Navigateur Windows ─► localhost:80 ─(WSL)─► conteneur bootcamp-control-plane:30080
   ─► Service traefik (NodePort 30080) ─► pod Traefik (entrypoint web :8000)
   ─► Gateway "main" (listener :8000) ─► HTTPRoute (host) ─► Service taskapi ─► pods
```

Dans le cloud, le Service de Traefik serait de type `LoadBalancer` et recevrait une IP publique.

---

## 2. Applications avec état

### 2.1 Volumes persistants

```
Pod ──volumeMounts──► PVC (demande : 1Gi, RWO, classe "standard")
                         │ binding
                         ▼
                        PV (ressource réelle : disque cloud, NFS, local-path…)
                         ▲ provisionné dynamiquement par
                     StorageClass (provisioner + paramètres + reclaimPolicy)
```

| Notion | À retenir |
|---|---|
| `accessModes` | `ReadWriteOnce` (un nœud), `ReadWriteOncePod`, `ReadOnlyMany`, `ReadWriteMany` (NFS, CephFS, EFS…) |
| `reclaimPolicy` | `Delete` (le disque est supprimé avec le PVC) ou `Retain` (à garder en prod pour les données critiques) |
| `volumeBindingMode: WaitForFirstConsumer` | le volume est créé dans la zone/sur le nœud où le pod est planifié |
| Expansion | `allowVolumeExpansion: true` → on peut agrandir un PVC |
| CSI | interface standard des drivers de stockage (EBS, PD, Azure Disk, Ceph, Longhorn…) |
| Snapshots | `VolumeSnapshot` (si le driver CSI le supporte) |

### 2.2 StatefulSet

Pour les applis qui ont besoin d'une **identité stable** :

| | Deployment | StatefulSet |
|---|---|---|
| Noms des pods | aléatoires (`taskapi-7d4b9-xk2p`) | ordinaux stables (`postgres-0`, `postgres-1`) |
| Stockage | partagé ou aucun | **un PVC par pod** via `volumeClaimTemplates`, qui le suit à la recréation |
| DNS | via le Service | DNS par pod via un **Service headless** : `postgres-0.postgres.ns.svc.cluster.local` |
| Ordre | parallèle | création/suppression ordonnées (0, 1, 2…) par défaut |
| Mise à jour | RollingUpdate classique | RollingUpdate en ordre inverse, `partition` pour du canary |

⚠ Un StatefulSet ne rend **pas** une base de données hautement disponible : il donne juste des briques stables. La réplication, le failover, les sauvegardes, c'est le travail d'un **opérateur** (CloudNativePG, Zalando Postgres Operator, Strimzi pour Kafka…) — ou d'un service managé (RDS, Cloud SQL…), souvent le bon choix en entreprise.

### 2.3 Jobs et CronJobs

```yaml
kind: Job
spec:
  backoffLimit: 3                 # tentatives avant échec
  activeDeadlineSeconds: 600      # durée max
  ttlSecondsAfterFinished: 3600   # nettoyage auto
  template: { spec: { restartPolicy: OnFailure, … } }
---
kind: CronJob
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Forbid       # pas de chevauchement
  successfulJobsHistoryLimit: 3
  timeZone: Europe/Paris
```

Cas d'usage : migrations de schéma, sauvegardes, traitements batch, purge.

---

## 3. Autoscaling

| Niveau | Outil | Ce qu'il fait |
|---|---|---|
| Pods (horizontal) | **HPA** | ajuste le nombre de réplicas selon CPU/mémoire (metrics-server) ou des métriques custom/externes |
| Pods (vertical) | **VPA** | recommande/ajuste les requests (redémarre les pods en mode Auto ; *in-place resize* arrive) |
| Événementiel | **KEDA** | scale sur la longueur d'une file Kafka/RabbitMQ/SQS, une requête Prometheus… y compris **à zéro** |
| Nœuds | Cluster Autoscaler, **Karpenter** | ajoute/retire des nœuds quand des pods sont Pending / les nœuds sous-utilisés |

**Formule HPA** : `réplicas_voulus = ceil(réplicas_actuels × valeur_actuelle / valeur_cible)`.
L'utilisation CPU est calculée **en % de la request** → sans request CPU, pas d'HPA possible.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: taskapi }
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }
  behavior:
    scaleDown: { stabilizationWindowSeconds: 120 }   # évite le yo-yo
```

⚠ Si un HPA gère `replicas`, **ne fixe pas** `replicas` dans le Deployment versionné (ou ignore ce champ dans Argo CD), sinon chaque déploiement réinitialise le nombre de pods.

**PodDisruptionBudget** : limite les interruptions *volontaires* (drain de nœud pour maintenance, mise à jour du cluster) : `minAvailable: 1` → `kubectl drain` attendra plutôt que de tuer le dernier pod.

---

## 4. Sécurité

### 4.1 RBAC : qui peut faire quoi

```
  Sujet (User, Group, ServiceAccount)
      │  lié par
  RoleBinding (dans un namespace)   /   ClusterRoleBinding (tout le cluster)
      │  à
  Role (verbes × ressources, dans un ns)  /  ClusterRole (cluster ou réutilisable)
```

```yaml
kind: Role
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "pods/log", "deployments"]
    verbs: ["get", "list", "watch"]
```

- Kubernetes n'a **pas d'objet User** : les humains sont authentifiés par certificat, OIDC (SSO), ou via le cloud (IAM). Les **ServiceAccounts** sont les identités des pods (jeton monté automatiquement → `automountServiceAccountToken: false` si l'appli n'appelle pas l'API).
- Test : `kubectl auth can-i delete pods -n taskapi --as system:serviceaccount:taskapi:lecteur`.
- Principe du **moindre privilège** ; méfiance envers `*`, `secrets`, `pods/exec`, `escalate`, `bind`, `impersonate`.

### 4.2 Pod Security Standards (PSS) et securityContext

Trois profils, appliqués par l'admission **Pod Security** via des labels de namespace :

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted   # refuse les pods non conformes
    pod-security.kubernetes.io/warn: restricted      # avertit à l'apply
```

| Profil | Interdit notamment |
|---|---|
| `privileged` | rien |
| `baseline` | `privileged`, `hostNetwork/hostPID`, hostPath, capabilities dangereuses |
| `restricted` | + root, escalade de privilèges, capabilities hors `NET_BIND_SERVICE`, seccomp non défini |

Un pod conforme `restricted` :

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    fsGroup: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
```

Pour des politiques plus riches (« images uniquement depuis ghcr.io/monorg », « label team obligatoire ») : **Kyverno**, **OPA Gatekeeper**, ou les **ValidatingAdmissionPolicies** (CEL) natives.

### 4.3 NetworkPolicy : le pare-feu des pods

Par défaut, **tous les pods peuvent parler à tous les pods** du cluster. Une NetworkPolicy sélectionne des pods et n'autorise que les flux listés (dès qu'un pod est sélectionné par une policy pour une direction, tout le reste est refusé dans cette direction).

```yaml
# 1. Tout bloquer en entrée dans le namespace
kind: NetworkPolicy
spec: { podSelector: {}, policyTypes: [Ingress] }
---
# 2. Autoriser Traefik → taskapi:8000
spec:
  podSelector: { matchLabels: { app.kubernetes.io/name: taskapi } }
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: traefik } }
      ports: [{ port: 8000 }]
```

- Ce sont des **règles additives** (union). Pas de « deny » explicite (sauf CRD Cilium/Calico).
- En **egress**, ne pas oublier le **DNS** (UDP/TCP 53 vers kube-system), sinon plus rien ne résout.
- Elles ne sont appliquées que si le **CNI** les supporte (Calico, Cilium, kindnet récent ; pas Flannel seul).

---

## 5. Helm : le gestionnaire de paquets

### 5.1 Concepts

| Terme | Sens |
|---|---|
| **Chart** | paquet : templates + `values.yaml` + métadonnées |
| **Values** | paramètres (défauts du chart, surchargés par `-f mes-values.yaml` et `--set`) |
| **Release** | une installation nommée d'un chart dans un namespace (historique des révisions stocké dans des Secrets) |
| **Repository** | index HTTP de charts, ou registre **OCI** (`oci://ghcr.io/…`) |

```
charts/taskapi/
├── Chart.yaml            # name, version (du chart, SemVer), appVersion (de l'appli)
├── values.yaml           # valeurs par défaut documentées
├── values.schema.json    # (optionnel) validation des values
├── templates/
│   ├── _helpers.tpl      # fonctions réutilisables (noms, labels)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── NOTES.txt         # message affiché après install
│   └── tests/            # helm test
└── charts/               # dépendances (sous-charts)
```

### 5.2 Templates (Go templates + Sprig)

```yaml
metadata:
  name: {{ include "taskapi.fullname" . }}
  labels: {{- include "taskapi.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
```

Objets intégrés : `.Values`, `.Release` (Name, Namespace, Revision), `.Chart`, `.Capabilities` (version K8s, APIs disponibles), `.Files`. Le `-` dans `{{-` supprime les espaces : l'indentation YAML est **la** source d'erreurs n°1 → `helm template` et `helm lint` systématiquement.

L'annotation `checksum/config` est l'astuce classique pour **redémarrer les pods quand la config change**.

### 5.3 Cycle de vie

```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm search repo traefik --versions | head
helm show values traefik/traefik > defaults.yaml          # TOUJOURS lire les values d'un chart
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f values.yaml --version X.Y.Z --wait
helm list -A
helm get values traefik -n traefik                        # values appliquées
helm get manifest traefik -n traefik                      # YAML réellement envoyé
helm history traefik -n traefik
helm rollback traefik 1 -n traefik
helm uninstall traefik -n traefik
helm template ./charts/taskapi -f values-dev.yaml         # rendu local, sans cluster
helm lint ./charts/taskapi
```

- `upgrade --install` : idempotent (installe ou met à jour) → à utiliser en CI.
- **Helm 4** (fin 2025) : `--atomic` devient `--rollback-on-failure`, *server-side apply* par défaut pour les nouvelles releases, plugins revus, OCI par défaut. Les charts existants (API v2) restent compatibles.
- Hooks (`helm.sh/hook: pre-upgrade`) pour des migrations, `crds/` installés avant le reste (mais **jamais mis à jour** par Helm : piège classique).
- **Épingle toujours `--version`** des charts tiers.

---

## 6. Kustomize : personnaliser sans templates

Intégré à kubectl (`kubectl apply -k`). Principe : des **YAML Kubernetes valides** + des **patchs** par environnement.

```
k8s/kustomize/
├── base/
│   ├── kustomization.yaml       resources: [deployment.yaml, service.yaml, …]
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/kustomization.yaml   resources: [../../base] + namespace + images + patches
    └── prod/kustomization.yaml
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: taskapi-prod
resources: [../../base]
images:
  - name: ghcr.io/tadeyayaoye/taskapi
    newTag: 1a2b3c4                 # ← ce que la CI modifie : kustomize edit set image …
replicas:
  - { name: taskapi, count: 3 }
configMapGenerator:
  - name: taskapi-config
    behavior: merge
    literals: [APP_ENV=prod, LOG_LEVEL=WARNING]
patches:
  - path: patch-resources.yaml      # strategic merge patch
  - target: { kind: HTTPRoute, name: taskapi }
    patch: |-                       # JSON patch (RFC 6902)
      - op: replace
        path: /spec/hostnames/0
        value: taskapi.localhost
```

- `configMapGenerator` ajoute un **suffixe de hash** au nom (`taskapi-config-7g8h9k`) et met à jour les références → un changement de config **déclenche un rollout**.
- `components` : morceaux optionnels réutilisables (ex. « activer les traces »).
- `kustomize build overlays/prod | kubectl diff -f -` avant d'appliquer.

### Helm ou Kustomize ?

| Helm | Kustomize |
|---|---|
| distribuer un logiciel à des tiers (paramétrable, versionné) | personnaliser **tes** manifests par environnement |
| logique (conditions, boucles) | pas de logique : du YAML pur, lisible, diffable |
| cycle de vie (release, rollback, hooks) | pas d'état : `apply` simple |
| templates parfois illisibles | patchs parfois verbeux |

En pratique (et dans ce bootcamp) : **Helm pour les briques tierces** (Traefik, Argo CD, Prometheus…), **Kustomize pour nos applis** dans le repo GitOps. Kustomize peut aussi « inflater » un chart Helm (`helmCharts:`), et Argo CD sait faire les deux.

---

## 7. Étendre Kubernetes : CRD et opérateurs

Une **CustomResourceDefinition** ajoute un nouveau type d'objet à l'API (`kind: Gateway`, `kind: ServiceMonitor`, `kind: Application`…). Un **opérateur** = CRD + contrôleur qui encode le savoir-faire d'exploitation (installer, sauvegarder, failover, upgrader) dans une boucle de réconciliation. Tu en utiliseras plusieurs : Traefik (Gateway API), Prometheus Operator, Argo CD, Sealed Secrets.

---

## Pièges classiques

- HTTPRoute ignorée : `parentRefs` vers une Gateway d'un autre namespace qui n'autorise pas ce namespace (`allowedRoutes`), ou hostname non couvert par le listener → regarder `kubectl describe httproute` (conditions `Accepted`, `ResolvedRefs`).
- PVC `Pending` : pas de StorageClass par défaut, ou `WaitForFirstConsumer` (normal tant qu'aucun pod ne l'utilise).
- Supprimer un StatefulSet ne supprime **pas** ses PVC (sécurité) → penser à les nettoyer.
- HPA à `<unknown>` : metrics-server absent ou pas de request CPU.
- `restricted` refuse le pod Postgres officiel (il démarre en root) → `runAsUser` + `fsGroup` adaptés.
- NetworkPolicy « default deny » posée → Prometheus ne scrape plus, les probes passent (le kubelet n'est pas filtré) mais l'appli ne joint plus le DNS si on a bloqué l'egress.
- Helm : valeurs mal indentées, `crds/` jamais mis à jour, chart non épinglé qui change de version majeure.

---

## Pour aller plus loin

- [Gateway API — guides](https://gateway-api.sigs.k8s.io/guides/)
- [Ingress NGINX Retirement (blog Kubernetes)](https://kubernetes.io/blog/)
- [Helm — Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kustomize — exemples](https://github.com/kubernetes-sigs/kustomize/tree/master/examples)
- [Network Policy Editor (visuel)](https://editor.networkpolicy.io/)
