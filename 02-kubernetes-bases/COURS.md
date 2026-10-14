# Module 02 — Kubernetes : architecture et objets fondamentaux

> **Objectif** : savoir expliquer ce qui se passe *dans* le cluster quand tu fais `kubectl apply`, maîtriser les objets du quotidien (Pod, Deployment, Service, ConfigMap, Secret), régler probes et ressources, et diagnostiquer méthodiquement un pod en échec.
>
> **Durée** : cours ~2 h · labs ~3 h · quiz 30 min

---

## 1. Pourquoi un orchestrateur ?

Docker lance des conteneurs sur **une** machine. En production il faut en plus : répartir sur plusieurs machines, redémarrer ce qui tombe, remplacer un nœud mort, mettre à jour sans coupure, répartir le trafic, scaler, gérer config et secrets… Kubernetes fait tout cela à partir d'un **état désiré déclaratif**.

### Le principe qui explique TOUT : la boucle de réconciliation

```
          ┌────────────── tu déclares ──────────────┐
          ▼                                          │
   ÉTAT DÉSIRÉ (spec)                        kubectl apply -f
   "3 réplicas de taskapi:v2"                        │
          │                                          │
          ▼                                          │
   ┌─────────────┐  observe   ┌───────────────┐      │
   │ Contrôleur  │◄───────────│ ÉTAT RÉEL     │      │
   │ (boucle     │            │ (status)      │      │
   │  infinie)   │──agit────► │ "2 pods OK"   │      │
   └─────────────┘            └───────────────┘
        compare → crée 1 pod → recompare → … jusqu'à convergence
```

Chaque objet a un `spec` (ce que tu veux) et un `status` (ce qui est). Des **contrôleurs** comparent en permanence et agissent pour converger. C'est **idempotent** et **auto-réparateur** — et c'est exactement le même principe qu'Argo CD (module 08) appliqué à Git.

---

## 2. Architecture

```
┌──────────────────────── CONTROL PLANE ────────────────────────┐
│                                                               │
│  kube-apiserver ◄──── kubectl, contrôleurs, kubelets ────     │
│   │  (seul composant qui parle à etcd ; authn, authz,         │
│   │   admission, validation ; API REST + watch)               │
│   ▼                                                           │
│  etcd  (base clé-valeur distribuée, Raft : TOUT l'état)       │
│                                                               │
│  kube-scheduler        choisit un nœud pour chaque pod Pending│
│  kube-controller-manager  Deployment, ReplicaSet, Node, Job…  │
│  cloud-controller-manager LoadBalancer, volumes, nœuds cloud  │
└───────────────────────────────────────────────────────────────┘
               ▲ watch / update status
┌──────────── NŒUD (worker) ────────────┐   ┌──── NŒUD ────┐
│ kubelet   : fait tourner les pods     │   │     …        │
│             assignés (via CRI)        │   └──────────────┘
│ container runtime : containerd        │
│ kube-proxy : règles iptables/nftables │
│             pour les Services         │
│ CNI plugin : réseau des pods          │
│ CSI plugin : volumes                  │
└───────────────────────────────────────┘
```

### Ce qui se passe lors d'un `kubectl apply -f deployment.yaml`

1. `kubectl` envoie le manifeste à l'**API server** (HTTPS, avec ton certificat/token du kubeconfig).
2. API server : **authentification** → **autorisation (RBAC)** → **admission** (mutating puis validating webhooks, Pod Security…) → validation du schéma → écriture dans **etcd**.
3. Le **contrôleur Deployment** voit (watch) le nouvel objet → crée un **ReplicaSet**.
4. Le **contrôleur ReplicaSet** crée N **Pods** (sans nœud : `Pending`).
5. Le **scheduler** filtre les nœuds (ressources dispo, taints, affinités…), les score, et écrit `nodeName` dans le pod.
6. Le **kubelet** du nœud choisi voit le pod → demande à **containerd** de tirer l'image et de créer les conteneurs, le **CNI** attribue une IP.
7. Le kubelet exécute les **probes** et remonte le `status`. Quand la readiness est OK, le contrôleur **EndpointSlice** ajoute l'IP du pod derrière le Service.

> À savoir réciter en entretien : c'est LA question d'architecture classique.

### Les 4 modèles réseau de Kubernetes

1. Chaque pod a sa **propre IP**, joignable par tous les autres pods **sans NAT** (assuré par le CNI : kindnet ici ; Calico, Cilium, Flannel ailleurs).
2. Les conteneurs d'un même pod partagent l'IP et `localhost`.
3. Les **Services** offrent une IP virtuelle stable + DNS devant des pods éphémères.
4. L'**Ingress / Gateway API** expose le HTTP vers l'extérieur (module 03).

---

## 3. Le langage des manifestes

```yaml
apiVersion: apps/v1          # groupe/version de l'API (kubectl api-resources)
kind: Deployment             # type d'objet
metadata:
  name: taskapi
  namespace: taskapi
  labels:                    # clé/valeur, servent aux SÉLECTEURS
    app.kubernetes.io/name: taskapi
  annotations:               # métadonnées libres (outils), non sélectionnables
    team: platform
spec: { … }                  # état désiré
status: { … }                # rempli par Kubernetes, jamais par toi
```

- **Labels + sélecteurs** = la colle de Kubernetes : un Service trouve ses pods par label, un Deployment ses ReplicaSets, une NetworkPolicy ses cibles… Une faute de frappe dans un label = un Service sans endpoints (bug n°1 du debug).
- Labels recommandés : `app.kubernetes.io/name`, `…/instance`, `…/version`, `…/component`, `…/part-of`, `…/managed-by`.
- **Namespaces** : cloisonnement logique (noms, quotas, RBAC, NetworkPolicies). Ce n'est pas une frontière de sécurité forte à lui seul.
- `kubectl explain deployment.spec.strategy --recursive` : la doc de chaque champ, hors ligne. Ton meilleur ami.

---

## 4. Les workloads

### 4.1 Pod

Plus petite unité déployable : **un ou plusieurs conteneurs** qui partagent réseau (IP, localhost) et volumes, et sont toujours planifiés ensemble.

- **Init containers** : s'exécutent avant les conteneurs principaux, séquentiellement (attendre une dépendance, préparer des fichiers, migrations).
- **Sidecars** (natifs depuis 1.29 : init container avec `restartPolicy: Always`) : proxy de service mesh, agent de logs…
- Phases : `Pending` → `Running` → `Succeeded`/`Failed` (+ `Unknown`). Les états de conteneur (`Waiting: CrashLoopBackOff`, `ImagePullBackOff`…) sont plus parlants.
- Un pod nu n'est **jamais recréé** s'il meurt ou si son nœud tombe. On ne crée donc jamais de pods directement, mais des contrôleurs.

### 4.2 ReplicaSet et Deployment

- **ReplicaSet** : maintient N pods identiques (sélecteur + template).
- **Deployment** : gère des ReplicaSets pour faire des **mises à jour progressives** et des **rollbacks**. Chaque changement du *template* de pod (image, env, ressources…) crée un nouveau ReplicaSet.

```
Deployment taskapi
 ├── ReplicaSet taskapi-7d4b9 (v1)  replicas: 3 → 2 → 1 → 0
 └── ReplicaSet taskapi-5f6c8 (v2)  replicas: 0 → 1 → 2 → 3
```

Stratégie `RollingUpdate` :

| Paramètre | Sens | Valeur prudente |
|---|---|---|
| `maxSurge` | pods en **plus** du nombre voulu pendant la mise à jour | `1` ou `25%` |
| `maxUnavailable` | pods **en moins** tolérés | `0` → jamais moins de capacité ✅ |

Avec `maxUnavailable: 0`, si les nouveaux pods ne deviennent jamais *Ready*, le rollout **bloque** et l'ancienne version continue de servir : c'est ta protection contre un mauvais déploiement (à condition d'avoir une **readiness probe** sérieuse !). `progressDeadlineSeconds` (600 s) marque alors le déploiement en échec.

`Recreate` : tue tout puis recrée (coupure ; utile si deux versions ne peuvent pas coexister).

```bash
kubectl rollout status deploy/taskapi
kubectl rollout history deploy/taskapi
kubectl rollout undo deploy/taskapi [--to-revision=2]
kubectl rollout restart deploy/taskapi      # recrée les pods (ex. pour relire un Secret)
```

### 4.3 Les autres (vus au module 03)

`StatefulSet` (identité et stockage stables), `DaemonSet` (un pod par nœud : agents), `Job` / `CronJob` (tâches finies / planifiées).

---

## 5. Services et DNS

Les pods sont éphémères (IP qui change à chaque recréation). Le **Service** fournit une adresse stable.

| Type | Accessible depuis | Usage |
|---|---|---|
| `ClusterIP` (défaut) | l'intérieur du cluster | communication entre services |
| `NodePort` | `<IP de n'importe quel nœud>:30000-32767` | tests, ou derrière un LB externe (notre cas avec kind) |
| `LoadBalancer` | une IP externe fournie par le cloud (ou MetalLB, cloud-provider-kind) | exposition directe |
| `ExternalName` | alias DNS vers un nom externe | |
| *headless* (`clusterIP: None`) | DNS qui renvoie directement les IP des pods | StatefulSets, bases distribuées |

```yaml
spec:
  selector: { app.kubernetes.io/name: taskapi }   # quels pods
  ports:
    - name: http
      port: 80            # port du Service
      targetPort: http    # port du conteneur (nommé = plus robuste)
```

- **DNS** (CoreDNS) : `taskapi` (même namespace), `taskapi.taskapi-dev`, `taskapi.taskapi-dev.svc.cluster.local` (FQDN).
- **EndpointSlices** : la liste des IP:port des pods *Ready* sélectionnés. `kubectl get endpointslices -l kubernetes.io/service-name=taskapi`. Vide = problème de label ou de readiness.
- **kube-proxy** programme le noyau (iptables, IPVS ou nftables) pour que l'IP virtuelle du Service soit répartie (aléatoirement) sur les endpoints. Cilium peut le remplacer entièrement (eBPF).
- `kubectl port-forward svc/taskapi 8080:80` : tunnel depuis ton poste, pratique pour le debug (passe par l'API server).

---

## 6. Configuration : ConfigMap et Secret

```yaml
envFrom:
  - configMapRef: { name: taskapi-config }           # toutes les clés → variables d'env
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef: { name: taskapi-db, key: password }
volumeMounts:
  - { name: config, mountPath: /etc/taskapi, readOnly: true }   # ou en fichiers
```

- Un **Secret n'est PAS chiffré** par défaut : c'est du **base64** (encodage, pas chiffrement). Protections réelles : RBAC strict sur les Secrets, chiffrement au repos d'etcd (`EncryptionConfiguration` / KMS), et ne jamais les stocker en clair dans Git → Sealed Secrets, SOPS, External Secrets (module 08).
- Variables d'environnement : lues **au démarrage** uniquement. Modifier le ConfigMap ne change rien aux pods en cours → `kubectl rollout restart`, ou mieux : un **nom de ConfigMap qui change avec son contenu** (hash suffix de Kustomize, module 03) qui déclenche un rollout automatique.
- Fichiers montés : mis à jour automatiquement (avec un délai), sauf en `subPath`.

---

## 7. Probes : santé et disponibilité

| Probe | Question | Si échec |
|---|---|---|
| **startupProbe** | « as-tu fini de démarrer ? » | les autres probes attendent ; au bout de `failureThreshold × periodSeconds` → redémarrage |
| **livenessProbe** | « es-tu bloqué ? » | **redémarrage** du conteneur |
| **readinessProbe** | « peux-tu recevoir du trafic ? » | retrait des **endpoints** du Service (pas de redémarrage) |

Types : `httpGet`, `tcpSocket`, `exec`, `grpc`.

Règles d'or :
- La **liveness ne teste jamais une dépendance externe** (base, API tierce) → sinon redémarrages en cascade.
- La **readiness** peut tester les dépendances indispensables.
- Pas de liveness du tout vaut mieux qu'une liveness mal réglée (délais trop courts = boucle de redémarrages au moindre pic de charge).
- Applis lentes à démarrer (JVM) : `startupProbe` plutôt qu'un énorme `initialDelaySeconds`.

---

## 8. Ressources : requests, limits, QoS

```yaml
resources:
  requests: { cpu: 50m, memory: 96Mi }    # RÉSERVÉ : utilisé par le scheduler
  limits:   { memory: 256Mi }              # PLAFOND : appliqué par le cgroup
```

- **CPU** en millicores (`1000m` = 1 vCPU). Dépasser une limite CPU → **throttling** (lenteur). Beaucoup d'équipes ne mettent **pas de limite CPU** (pour profiter du CPU libre) mais toujours une **request**.
- **Mémoire** en `Mi`/`Gi`. Dépasser la limite → **OOMKilled**, redémarrage. Toujours une limite mémoire.
- Le scheduler place un pod uniquement si la **somme des requests** tient dans l'*allocatable* du nœud. Pas de request = le scheduler croit que le pod ne consomme rien → surcharge.

| Classe QoS | Condition | Éviction en cas de pression mémoire du nœud |
|---|---|---|
| `Guaranteed` | requests = limits (CPU et mémoire) pour tous les conteneurs | en dernier |
| `Burstable` | au moins une request | ensuite |
| `BestEffort` | aucune request ni limit | en premier |

`LimitRange` (valeurs par défaut par namespace) et `ResourceQuota` (plafond total par namespace) cadrent tout ça.

---

## 9. Placement (scheduling)

| Mécanisme | Sens |
|---|---|
| `nodeSelector` | « uniquement sur les nœuds avec ce label » |
| `affinity.nodeAffinity` | idem, avec opérateurs et préférences (`preferred…`) |
| `podAntiAffinity` | « pas sur le même nœud qu'un autre pod de ce type » |
| `topologySpreadConstraints` | ✅ répartir uniformément sur nœuds/zones |
| **taints / tolerations** | un nœud *repousse* les pods sauf ceux qui *tolèrent* sa taint (nœuds GPU, control plane…) |
| `priorityClassName` | priorité et préemption |

---

## 10. kubectl : les commandes qui comptent

```bash
kubectl config get-contexts / use-context kind-bootcamp     # quel cluster ?
kubectl get pods -A -o wide                                  # tous les namespaces, nœud + IP
kubectl get deploy,rs,pods,svc -n taskapi
kubectl describe pod <p>                                     # ÉVÉNEMENTS en bas : toujours lire
kubectl logs <p> [-c conteneur] [-f] [--previous]            # --previous : le crash d'avant
kubectl exec -it <p> -- sh
kubectl get events -n taskapi --sort-by=.lastTimestamp
kubectl get pod <p> -o yaml | yq '.status'
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl create deployment x --image=nginx --dry-run=client -o yaml > x.yaml   # générer un squelette
kubectl diff -f manifest.yaml                                # ce qui va changer
kubectl apply -f dossier/ (-k pour Kustomize)
kubectl debug -it <p> --image=nicolaka/netshoot --target=<conteneur>   # conteneur éphémère de debug
kubectl top pods / nodes                                     # nécessite metrics-server (module 03)
```

`apply` (déclaratif, fusion à 3 voies, idempotent) vs `create`/`replace` (impératif). En équipe et en GitOps : **toujours déclaratif**.

---

## 11. Méthode de diagnostic

```
Pod pas OK ?
│
├─ Pending ............ describe → Events : "Insufficient cpu/memory" (requests trop grosses),
│                       "didn't tolerate taint", "unbound PersistentVolumeClaim", nodeSelector impossible
├─ ImagePullBackOff ... nom/tag d'image faux, registre privé sans imagePullSecret, image non chargée dans kind
├─ CrashLoopBackOff ... logs --previous ; erreur appli, config/secret manquant, commande fausse,
│                       liveness trop agressive
├─ CreateContainerConfigError ... ConfigMap/Secret ou clé référencée inexistante
├─ OOMKilled .......... limite mémoire trop basse (ou fuite)
├─ Running mais 0/1 READY ... la readiness échoue : describe (message de la probe), logs, dépendance
└─ Running + Ready mais le Service ne répond pas
                     → endpointslices vides ? (sélecteur ≠ labels) ; targetPort faux ;
                       NetworkPolicy ; test depuis un pod : kubectl run tmp --rm -it --image=curlimages/curl -- sh
```

---

## 12. kind : Kubernetes dans Docker

- Chaque **nœud** est un **conteneur Docker** (image `kindest/node`) qui contient systemd, containerd, kubelet. Le control plane est installé par **kubeadm**.
- Les images locales ne sont pas visibles du cluster : `kind load docker-image taskapi:dev --name bootcamp` les copie dans le containerd de chaque nœud. Avec `imagePullPolicy: IfNotPresent` (défaut si le tag n'est pas `latest`).
- `extraPortMappings` : publie un port d'un nœud-conteneur sur l'hôte → c'est ainsi qu'on rendra le cluster joignable sur `http://*.localhost` (module 03).
- Stockage : `local-path-provisioner` (StorageClass `standard`) fournit des volumes sur le disque du nœud.
- CNI : `kindnet` (gère aussi les NetworkPolicies dans les versions récentes de kind).

Alternatives locales : minikube, k3d (k3s dans Docker), Rancher Desktop, Docker Desktop K8s, MicroK8s.

---

## Pour aller plus loin

- [Kubernetes docs — Concepts](https://kubernetes.io/docs/concepts/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [A visual guide on troubleshooting Kubernetes deployments (learnk8s)](https://learnk8s.io/troubleshooting-deployments)
