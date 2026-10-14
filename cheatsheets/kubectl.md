# kubectl — fiche mémo

```bash
# Contexte
kubectl config get-contexts           kubectl config use-context kind-bootcamp
kubectl config set-context --current --namespace=taskapi-dev      # ou alias : kns taskapi-dev

# Lire
kubectl get pods -A -o wide           kubectl get deploy,rs,po,svc,ep -n ns
kubectl get po --show-labels -l app.kubernetes.io/name=taskapi
kubectl get po -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl get po -o custom-columns=NOM:.metadata.name,QOS:.status.qosClass,NODE:.spec.nodeName
kubectl describe po <p>               # ← lire les Events
kubectl get events -n ns --sort-by=.lastTimestamp
kubectl logs <p> [-c c] [-f] [--previous] [--since=10m]   kubectl logs -l app=x --prefix --tail=20
kubectl top nodes / pods --sort-by=memory
kubectl explain deploy.spec.strategy --recursive
kubectl api-resources                 kubectl auth can-i --list --as system:serviceaccount:ns:sa

# Écrire
kubectl apply -f f.yaml / -f dir/ / -k overlay/        kubectl diff -f f.yaml
kubectl create deploy x --image=nginx --replicas=2 --dry-run=client -o yaml > x.yaml
kubectl create secret generic s --from-literal=k=v --dry-run=client -o yaml
kubectl delete -f f.yaml              kubectl delete po <p> --grace-period=0 --force   # ⚠ dernier recours

# Déploiements
kubectl rollout status / history / undo [--to-revision=N] / restart deploy/x
kubectl set image deploy/x c=img:tag  kubectl scale deploy/x --replicas=3
kubectl set resources deploy/x --limits=memory=256Mi

# Debug
kubectl exec -it <p> -- sh            kubectl port-forward svc/x 8000:80
kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- sh
kubectl debug -it <p> --image=nicolaka/netshoot --target=<conteneur>
kubectl debug node/<n> -it --image=busybox

# Nœuds
kubectl cordon / uncordon <n>         kubectl drain <n> --ignore-daemonsets --delete-emptydir-data
kubectl taint node <n> k=v:NoSchedule[-]
```

**Diagnostic** : Pending → `describe` (ressources, taints, PVC) · ImagePullBackOff → nom/tag/registre · CrashLoopBackOff → `logs --previous` · CreateContainerConfigError → ConfigMap/Secret · OOMKilled → limite mémoire · 0/1 Ready → readiness · Service muet → `get endpointslices` (labels !).

kind : `kind create/delete cluster --name x` · `kind load docker-image img --name x` · `kind get clusters` · `docker exec -it x-control-plane crictl ps`.
