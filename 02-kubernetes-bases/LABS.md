# Module 02 — Labs Kubernetes (bases)

> ⏱ ~3 h · Prérequis : module 01 terminé (`taskapi:dev` existe). Arrête la stack Compose pour libérer de la RAM : `docker compose down`.

---

## Lab 2.1 — Créer et explorer le cluster (≈ 25 min)

```bash
cat 02-kubernetes-bases/kind/kind-config.yaml
make cluster-up                 # = kind create cluster --config 02-kubernetes-bases/kind/kind-config.yaml
kubectl config current-context  # kind-bootcamp
kubectl get nodes -o wide
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'   # les nœuds sont des conteneurs !
```

Explore le control plane :

```bash
kubectl get pods -n kube-system -o wide
# Repère : etcd, kube-apiserver, kube-controller-manager, kube-scheduler (sur le control-plane),
#          kube-proxy et kindnet (un par nœud : ce sont des DaemonSets), coredns
kubectl get ds -n kube-system
docker exec -it bootcamp-control-plane bash
  ls /etc/kubernetes/manifests          # pods STATIQUES du control plane, lancés directement par le kubelet
  crictl ps                             # conteneurs vus par containerd (pas de docker ici !)
  systemctl status kubelet --no-pager
  exit
kubectl api-resources | head -40
kubectl explain pod.spec.containers.readinessProbe
```

Où est ton kubeconfig, et qu'y a-t-il dedans ?

```bash
kubectl config view --minify      # serveur API, certificat client (ton identité)
```

---

## Lab 2.2 — Pods : impératif, puis déclaratif (≈ 20 min)

```bash
kubectl run hello --image=nginx:alpine --port 80
kubectl get pod hello -o wide -w            # Ctrl+C quand Running
kubectl describe pod hello | tail -15       # lis les Events : scheduling, pull, start
kubectl logs hello
kubectl exec -it hello -- sh -c 'hostname; cat /etc/resolv.conf'
kubectl port-forward pod/hello 8081:80 &    # puis http://localhost:8081 dans Windows
kill %1
kubectl delete pod hello                    # il ne revient pas : aucun contrôleur ne le surveille
```

Générer un squelette YAML au lieu de l'écrire de mémoire :

```bash
kubectl create deployment demo --image=nginx:alpine --replicas=3 --dry-run=client -o yaml > /tmp/demo.yaml
kubectl apply -f /tmp/demo.yaml
kubectl get deploy,rs,pods -l app=demo
kubectl delete pod -l app=demo --wait=false; kubectl get pods -l app=demo -w   # le ReplicaSet recrée
kubectl delete -f /tmp/demo.yaml
```

---

## Lab 2.3 — Déployer taskapi + Postgres (≈ 45 min)

Charge ton image dans le cluster :

```bash
kind load docker-image taskapi:dev --name bootcamp
docker exec bootcamp-worker crictl images | grep taskapi
```

Écris tes manifests dans `k8s/m02/` (un fichier par ressource, préfixés pour l'ordre) :

- `00-namespace.yaml` — namespace `taskapi`
- `10-postgres.yaml` — Deployment `postgres:17-alpine` (stratégie `Recreate`, volume `emptyDir`, readiness `pg_isready`) + Service `postgres`
- `20-configmap.yaml` — `APP_ENV`, `LOG_LEVEL`, `DB_HOST=postgres`, `DB_NAME`, `DB_USER`, `CHAOS_ENABLED=true`
- `30-deployment.yaml` — taskapi, 2 réplicas, `maxUnavailable: 0`, startup/liveness/readiness probes, requests/limits, `DB_PASSWORD` depuis le Secret
- `40-service.yaml` — ClusterIP port 80 → port nommé `http`

Le Secret ne va **pas** dans Git :

```bash
kubectl apply -f k8s/m02/00-namespace.yaml
kubectl -n taskapi create secret generic taskapi-db --from-literal=password="$(openssl rand -hex 16)"
kubectl -n taskapi get secret taskapi-db -o jsonpath='{.data.password}' | base64 -d; echo   # base64 ≠ chiffrement
kubectl apply -f k8s/m02/
kubectl -n taskapi get pods -w
```

Teste :

```bash
kubectl -n taskapi port-forward svc/taskapi 8000:80 &
curl -s localhost:8000/readyz
curl -s -X POST localhost:8000/api/tasks -H 'content-type: application/json' -d '{"title":"dans kube !"}'
curl -s localhost:8000/ | jq
kill %1
```

Depuis l'intérieur du cluster (DNS) :

```bash
kubectl -n taskapi run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  sh -c 'curl -s taskapi/version; echo; curl -s taskapi.taskapi.svc.cluster.local/healthz'
kubectl -n taskapi get endpointslices
```

Observe la répartition de charge : quel pod répond ?

```bash
for i in $(seq 6); do kubectl -n taskapi exec deploy/taskapi -- python -c \
  "import urllib.request,json; print(urllib.request.urlopen('http://taskapi/').status)"; done
kubectl -n taskapi logs -l app.kubernetes.io/name=taskapi --prefix --tail=3
```

**Le problème du emptyDir :**

```bash
kubectl -n taskapi delete pod -l app.kubernetes.io/name=postgres
kubectl -n taskapi rollout status deploy/postgres
# refais un port-forward puis GET /api/tasks : la liste est vide. Données perdues → module 03.
```

---

## Lab 2.4 — Probes et ressources en action (≈ 30 min)

**Readiness qui échoue** — que se passe-t-il quand la base tombe ?

```bash
kubectl -n taskapi scale deploy/postgres --replicas=0
kubectl -n taskapi get pods -w            # les pods taskapi passent 0/1 READY, sans redémarrer (RESTARTS = 0)
kubectl -n taskapi get endpointslices     # plus aucun endpoint "ready"
kubectl -n taskapi describe pod -l app.kubernetes.io/name=taskapi | grep -A2 Readiness
kubectl -n taskapi scale deploy/postgres --replicas=1
```

**Liveness** — que se passe-t-il si le process se bloque ? On simule en envoyant SIGSTOP (gel) au process :

```bash
POD=$(kubectl -n taskapi get pod -l app.kubernetes.io/name=taskapi -o name | head -1)
kubectl -n taskapi debug -it $POD --image=busybox --target=taskapi -- kill -STOP 1
kubectl -n taskapi get pods -w            # ~30 s plus tard : RESTARTS +1
```

**OOMKilled** :

```bash
kubectl -n taskapi set resources deploy/taskapi --limits=memory=40Mi
kubectl -n taskapi get pods -w            # OOMKilled / CrashLoopBackOff
kubectl -n taskapi describe pod -l app.kubernetes.io/name=taskapi | grep -B2 -A4 "Last State"
kubectl -n taskapi rollout status deploy/taskapi --timeout=60s   # bloqué : maxUnavailable 0 protège les anciens pods
kubectl -n taskapi get pods               # les ANCIENS pods tournent toujours ✅
kubectl -n taskapi rollout undo deploy/taskapi
```

**QoS** :

```bash
kubectl -n taskapi get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
kubectl describe node bootcamp-worker | sed -n '/Allocated resources/,/Events/p'
```

---

## Lab 2.5 — Rolling update et rollback (≈ 20 min)

Construis une « v2 » (seule la version change) et charge-la :

```bash
docker build -t taskapi:v2 --build-arg APP_VERSION=2.0.0 app/
kind load docker-image taskapi:v2 --name bootcamp
kubectl -n taskapi set image deploy/taskapi taskapi=taskapi:v2
kubectl -n taskapi annotate deploy/taskapi kubernetes.io/change-cause="passage en v2" --overwrite
kubectl -n taskapi rollout status deploy/taskapi
kubectl -n taskapi get rs                 # deux ReplicaSets : l'ancien à 0
kubectl -n taskapi rollout history deploy/taskapi
```

Dans un 2e terminal, pendant le prochain rollout, surveille la disponibilité :

```bash
kubectl -n taskapi port-forward svc/taskapi 8000:80 &
while true; do curl -s -o /dev/null -w '%{http_code} ' localhost:8000/version; sleep 0.2; done
```

```bash
kubectl -n taskapi rollout undo deploy/taskapi
```

Combien de non-200 as-tu vus ? (Avec `port-forward` tu restes collé à un pod, donc tu peux voir une erreur quand *ce* pod s'arrête : c'est une limite du port-forward, pas du rollout. On refera le test proprement via la Gateway au module 03.)

---

## Lab 2.6 — Placement (≈ 20 min)

```bash
kubectl label node bootcamp-worker2 disk=ssd
kubectl -n taskapi patch deploy taskapi --type merge -p \
  '{"spec":{"template":{"spec":{"nodeSelector":{"disk":"ssd"}}}}}'
kubectl -n taskapi get pods -o wide        # tous sur worker2

kubectl taint node bootcamp-worker2 dedicated=db:NoSchedule
kubectl -n taskapi rollout restart deploy/taskapi
kubectl -n taskapi get pods -o wide        # Pending ! pourquoi ? (describe)

kubectl taint node bootcamp-worker2 dedicated=db:NoSchedule-     # retire la taint
kubectl -n taskapi patch deploy taskapi --type json -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
```

Ajoute à ton Deployment une `topologySpreadConstraints` (clé `kubernetes.io/hostname`, `maxSkew: 1`, `whenUnsatisfiable: ScheduleAnyway`) et vérifie la répartition avec 4 réplicas.

---

## Lab 2.7 — Debug : 7 pannes (≈ 30 min)

```bash
kubectl apply -f 02-kubernetes-bases/labs/broken.yaml
kubectl -n debug-lab get pods,svc
```

Pour **chacun** des 7 cas, note : symptôme → commande de diagnostic → cause → correction. Corrige en éditant (`kubectl -n debug-lab edit deploy caseN`) jusqu'à ce que tout soit Running/Ready et que les deux Services répondent :

```bash
kubectl -n debug-lab run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  sh -c 'curl -s -m 3 case1/healthz; echo; curl -s -m 3 case4/healthz'
```

> Corrigé : [solutions/README.md](solutions/README.md). Puis `kubectl delete ns debug-lab`.

---

## 🏁 Challenge (sans guide)

1. Ajoute un **init container** à taskapi qui attend que Postgres réponde (`busybox` + `nc -z postgres 5432` en boucle). Démontre son effet en redéployant avec Postgres à 0 réplica.
2. Ajoute un `LimitRange` au namespace qui impose des requests/limits par défaut, et un `ResourceQuota` (max 2 CPU de requests, 2 Gi de mémoire). Essaie de scaler taskapi à 20 réplicas : que se passe-t-il, où le vois-tu ?
3. Écris `k8s/m02/README.md` qui explique, en 10 lignes, le chemin d'une requête `curl taskapi/version` depuis un pod jusqu'au conteneur (DNS → ClusterIP → kube-proxy → endpoint → pod).

---

## ✅ Validation

```bash
make check-02
```
