# Module 03 — Labs Kubernetes avancé

> ⏱ ~3 h 30 · Prérequis : cluster `bootcamp` du module 02, image `taskapi:dev` chargée dans kind.
> Tu écris tes fichiers dans `k8s/platform/`, `k8s/m03/`, `charts/taskapi/` et `k8s/kustomize/`.

---

## Lab 3.1 — Plateforme : metrics-server, Traefik, Gateway API (≈ 35 min)

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

**metrics-server** (lis d'abord les valeurs par défaut) :

```bash
helm show values metrics-server/metrics-server | less
# écris k8s/platform/metrics-server-values.yaml (indice : kubelets auto-signés dans kind)
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
  -f k8s/platform/metrics-server-values.yaml --wait
kubectl top nodes        # peut prendre ~1 min
kubectl top pods -A --sort-by=memory | head
```

**Traefik** en contrôleur Gateway API :

```bash
helm show values traefik/traefik > /tmp/traefik-defaults.yaml    # ~1000 lignes : cherche service, ports, providers, gateway
# écris k8s/platform/traefik-values.yaml : Service NodePort 30080/30443, provider kubernetesGateway activé,
# gateway.enabled=false et gatewayClass.enabled=false (on les crée nous-mêmes)
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace \
  -f k8s/platform/traefik-values.yaml --wait
kubectl get crd | grep gateway.networking.k8s.io
kubectl -n traefik get svc traefik
```

> Si les CRD Gateway API n'apparaissent pas (dépend de la version du chart) :
> `kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml`

Écris `k8s/platform/gateway.yaml` (GatewayClass `traefik` avec `controllerName: traefik.io/gateway-controller`, Gateway `main` dans `traefik`, listener HTTP port **8000**, hostname `*.localhost`, routes acceptées depuis tous les namespaces) :

```bash
kubectl apply -f k8s/platform/gateway.yaml
kubectl get gatewayclass,gateway -A          # PROGRAMMED = True
kubectl -n traefik describe gateway main | sed -n '/Conditions/,$p'
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/    # 404 de Traefik : la chaîne fonctionne !
```

---

## Lab 3.2 — Migrer Postgres en StatefulSet (≈ 30 min)

On repart proprement dans le namespace `taskapi` en mode « restricted » :

```bash
kubectl delete -f k8s/m02/10-postgres.yaml
mkdir -p k8s/m03 && cp k8s/m02/{20-configmap,40-service}.yaml k8s/m03/
```

Écris :
- `k8s/m03/00-namespace.yaml` : le namespace `taskapi` avec les labels Pod Security `enforce/warn: restricted` ;
- `k8s/m03/05-rbac.yaml` : ServiceAccount `taskapi` (sans montage de token) ;
- `k8s/m03/10-postgres.yaml` : Service **headless** + **StatefulSet** avec `volumeClaimTemplates` (1Gi), conforme `restricted` (indice : l'utilisateur `postgres` de l'image alpine a l'UID **70**).

```bash
kubectl apply -f k8s/m03/00-namespace.yaml
kubectl apply -f k8s/m02/30-deployment.yaml --dry-run=server   # le Deployment du module 02 viole "restricted" : lis les avertissements
kubectl apply -f k8s/m03/05-rbac.yaml -f k8s/m03/10-postgres.yaml
kubectl -n taskapi get sts,pods,pvc
kubectl get pv
kubectl -n taskapi exec postgres-0 -- psql -U taskapi -c '\l'
```

Durcis ton Deployment (`k8s/m03/30-deployment.yaml`) : `securityContext` pod + conteneur, `readOnlyRootFilesystem` (+ emptyDir sur `/tmp`), `serviceAccountName`, `topologySpreadConstraints`, **pas de `replicas`** (l'HPA s'en chargera) :

```bash
kubectl apply -f k8s/m03/
kubectl -n taskapi rollout status deploy/taskapi
```

**Preuve de persistance :**

```bash
kubectl -n taskapi port-forward svc/taskapi 8000:80 &
curl -s -X POST localhost:8000/api/tasks -H 'content-type: application/json' -d '{"title":"je survis aux redémarrages"}'
kubectl -n taskapi delete pod postgres-0 && kubectl -n taskapi wait --for=condition=Ready pod/postgres-0 --timeout=90s
sleep 5; curl -s localhost:8000/api/tasks | jq '.[].title'
kill %1
```

---

## Lab 3.3 — Exposer via la Gateway (≈ 15 min)

Écris `k8s/m03/50-httproute.yaml` (host `taskapi.localhost`, parentRef `main`/`traefik`, section `web`).

```bash
kubectl apply -f k8s/m03/50-httproute.yaml
kubectl -n taskapi describe httproute taskapi | sed -n '/Conditions/,$p'    # Accepted, ResolvedRefs
curl -s http://taskapi.localhost/version
```

Ouvre http://taskapi.localhost/docs dans ton navigateur Windows. 🎉

Rejoue le test de disponibilité du module 02, cette fois via la Gateway :

```bash
while true; do curl -s -o /dev/null -w '%{http_code} ' http://taskapi.localhost/version; sleep 0.1; done
# dans un autre terminal :
kubectl -n taskapi rollout restart deploy/taskapi
```

Que des 200 ? Sinon, pourquoi ? (Indice : ordre de retrait des endpoints vs arrêt du process → hook `preStop: sleep 5`, une astuce très courante en prod.)

---

## Lab 3.4 — Sauvegardes : Job et CronJob (≈ 20 min)

Écris `k8s/m03/15-backup.yaml` : un PVC `pg-backups` et un CronJob `pg-backup` (toutes les 10 min, `concurrencyPolicy: Forbid`, `pg_dump -Fc` vers `/backups`, rétention 1 h, conforme `restricted`, label de pod `app.kubernetes.io/name: pg-backup`).

```bash
kubectl apply -f k8s/m03/15-backup.yaml
kubectl -n taskapi create job --from=cronjob/pg-backup backup-manuel   # déclenchement immédiat
kubectl -n taskapi logs -f job/backup-manuel
kubectl -n taskapi get cronjob,jobs
```

Bonus : écris un Job de **restauration** (`pg_restore --clean`) à partir du dernier dump.

---

## Lab 3.5 — Autoscaling (≈ 25 min)

Écris `k8s/m03/60-autoscaling.yaml` : HPA (2 → 6 réplicas, 60 % CPU) + PodDisruptionBudget (`minAvailable: 1`).

```bash
kubectl apply -f k8s/m03/60-autoscaling.yaml
kubectl -n taskapi get hpa -w              # TARGETS doit afficher un % (pas <unknown>)
```

Dans un 2e terminal, génère de la charge :

```bash
python3 scripts/load.py http://taskapi.localhost --duration 240 --concurrency 30
```

Observe `kubectl -n taskapi get hpa,pods -w` puis `kubectl -n taskapi describe hpa taskapi` (événements de scale). Après la charge, combien de temps avant la réduction ? Pourquoi ?

**PDB en action :**

```bash
kubectl drain bootcamp-worker --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n taskapi -o wide
kubectl uncordon bootcamp-worker
```

---

## Lab 3.6 — Sécurité : RBAC et NetworkPolicy (≈ 35 min)

**RBAC** : complète `05-rbac.yaml` avec un ServiceAccount `lecteur`, un Role (lecture seule sur pods, logs, services, deployments… mais **pas** les secrets) et un RoleBinding.

```bash
kubectl apply -f k8s/m03/05-rbac.yaml
SA=system:serviceaccount:taskapi:lecteur
kubectl auth can-i list pods      -n taskapi --as $SA    # yes
kubectl auth can-i get secrets    -n taskapi --as $SA    # no
kubectl auth can-i delete pods    -n taskapi --as $SA    # no
kubectl auth can-i list pods      -n kube-system --as $SA   # no
kubectl auth can-i --list -n taskapi --as $SA
```

Utilise réellement ce compte avec un jeton à durée limitée :

```bash
TOKEN=$(kubectl -n taskapi create token lecteur --duration=10m)
kubectl --token="$TOKEN" -n taskapi get pods            # OK
kubectl --token="$TOKEN" -n taskapi delete pod postgres-0   # Forbidden ✅
```

**NetworkPolicy** — d'abord, constate que tout est ouvert :

```bash
kubectl create ns intrus
kubectl -n intrus run nc --rm -it --image=busybox --restart=Never -- nc -zv -w 3 postgres.taskapi 5432   # open 😱
```

Écris `k8s/m03/70-networkpolicies.yaml` : default-deny en entrée, Traefik + `monitoring` → taskapi:8000, taskapi + pg-backup → postgres:5432.

```bash
kubectl apply -f k8s/m03/70-networkpolicies.yaml
kubectl -n intrus run nc --rm -it --image=busybox --restart=Never -- nc -zv -w 3 postgres.taskapi 5432   # timeout ✅
curl -s http://taskapi.localhost/readyz                                                                  # toujours OK ✅
kubectl -n taskapi create job --from=cronjob/pg-backup backup-apres-netpol && kubectl -n taskapi logs -f job/backup-apres-netpol
kubectl delete ns intrus
```

> Si le premier test passe toujours après la policy, ta version de kindnet n'applique pas les NetworkPolicies : note-le (en entreprise : Calico ou Cilium).

---

## Lab 3.7 — Écrire un chart Helm (≈ 40 min)

```bash
helm create /tmp/exemple && tree /tmp/exemple     # regarde ce que génère Helm (puis on fait le nôtre, plus simple)
```

Crée `charts/taskapi/` : `Chart.yaml`, `values.yaml` documenté, `templates/_helpers.tpl` (fullname, labels, selectorLabels), `configmap.yaml`, `deployment.yaml` (avec l'annotation `checksum/config`), `service.yaml` (+ ServiceAccount), `httproute.yaml` (conditionnel), `availability.yaml` (HPA conditionnel + PDB), `networkpolicy.yaml`, `servicemonitor.yaml` (conditionné à `.Capabilities.APIVersions.Has`), `NOTES.txt`, `tests/test-connection.yaml`.

```bash
helm lint charts/taskapi
helm template demo charts/taskapi | less                     # lis le rendu
helm template demo charts/taskapi --set autoscaling.enabled=true | grep -c HorizontalPodAutoscaler
```

Installe-le dans un autre namespace en réutilisant la base de `taskapi` :

```bash
kubectl create ns taskapi-helm
kubectl label ns taskapi-helm pod-security.kubernetes.io/enforce=restricted
kubectl -n taskapi get secret taskapi-db -o json | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp)' \
  | kubectl -n taskapi-helm apply -f -
kubectl apply -f k8s/m03/71-postgres-from-helm-ns.yaml        # à écrire : autoriser ce namespace vers Postgres
helm upgrade --install demo charts/taskapi -n taskapi-helm -f charts/values-lab.yaml --wait
helm test demo -n taskapi-helm
curl -s http://taskapi-helm.localhost/version
```

Cycle de vie :

```bash
helm upgrade demo charts/taskapi -n taskapi-helm -f charts/values-lab.yaml --set config.LOG_LEVEL=DEBUG
kubectl -n taskapi-helm get rs                 # nouveau ReplicaSet grâce au checksum
helm history demo -n taskapi-helm
helm rollback demo 1 -n taskapi-helm
helm get values demo -n taskapi-helm --all | head -20
helm uninstall demo -n taskapi-helm && kubectl delete ns taskapi-helm
```

---

## Lab 3.8 — Kustomize : base + overlays dev/prod (≈ 30 min)

C'est **la structure qui deviendra ton repo GitOps** au module 08. Crée :

```
k8s/kustomize/
├── apps/taskapi/base/    kustomization.yaml (configMapGenerator !), serviceaccount, deployment,
│                         service, httproute, autoscaling (HPA+PDB), networkpolicy
├── apps/postgres/base/   kustomization.yaml, postgres.yaml (Service headless + StatefulSet + NetworkPolicy)
└── envs/
    ├── dev/              namespace taskapi-dev, host taskapi-dev.localhost, HPA 1→3, LOG_LEVEL=DEBUG
    └── prod/             namespace taskapi-prod, host taskapi.localhost, requests/limits plus élevés
```

Dans la base, l'image est `ghcr.io/tadeyayaoye/taskapi` ; les overlays la remplacent par `taskapi:dev` (bloc `images:` avec `newName`/`newTag`).

```bash
kustomize build k8s/kustomize/envs/dev | less
kustomize build k8s/kustomize/envs/dev | grep -A3 "kind: ConfigMap"      # nom suffixé d'un hash
diff <(kustomize build k8s/kustomize/envs/dev) <(kustomize build k8s/kustomize/envs/prod)

kubectl create ns taskapi-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n taskapi-dev create secret generic taskapi-db --from-literal=password="$(openssl rand -hex 16)"
kubectl apply -k k8s/kustomize/envs/dev
kubectl -n taskapi-dev get all
curl -s http://taskapi-dev.localhost/version
```

Modifie `LOG_LEVEL` dans l'overlay dev, puis `kubectl diff -k k8s/kustomize/envs/dev` : observe que le **nom** du ConfigMap change et que le Deployment est donc modifié → rollout automatique.

Nettoie l'environnement dev (Argo CD le recréera au module 08) : `kubectl delete -k k8s/kustomize/envs/dev`.

---

## 🏁 Challenge (sans guide)

1. **Canary avec Gateway API** : déploie une 2e version (`taskapi:v2` du module 02) dans un Deployment `taskapi-canary` + Service, et route **10 %** du trafic dessus via `backendRefs` pondérés. Prouve la répartition avec une boucle `curl …/version | sort | uniq -c`.
2. Ajoute une **NetworkPolicy d'egress** à taskapi : seulement le DNS (kube-system, port 53 UDP/TCP) et Postgres. Vérifie que `curl https://github.com` échoue depuis le pod (`kubectl debug`).
3. Ajoute un `values.schema.json` à ton chart qui rend `image.repository` obligatoire et `replicaCount` entier ≥ 1. Teste avec `--set replicaCount=zero`.

---

## ✅ Validation

```bash
make check-03
```
