# Solutions du module 02

- `k8s/m02/` : manifests de taskapi + Postgres (à appliquer avec `kubectl apply -f k8s/m02/`).
- Le Secret n'est **pas** dans les fichiers : il se crée à la main (Lab 2.3), on ne commite jamais un Secret en clair.

## Corrigé du Lab 2.7 (debug)

| Cas | Symptôme | Commande qui le révèle | Cause | Correction |
|---|---|---|---|---|
| 1 | Pod Running/Ready mais le Service ne répond pas | `kubectl get endpointslices -n debug-lab -l kubernetes.io/service-name=case1` → aucun endpoint | sélecteur `app: cas1` ≠ label `app: case1` | corriger le sélecteur |
| 2 | `ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod` → Events : `pull access denied … taskapi:dve` | faute de frappe dans le tag | `taskapi:dev` |
| 3 | `CreateContainerConfigError` | `describe pod` → `couldn't find key DB_URL in ConfigMap` | clé inexistante | `key: DATABASE_URL` |
| 4 | Pod OK, endpoints présents, mais `connection refused` | `kubectl run tmp --rm -it --image=curlimages/curl -n debug-lab -- curl -sv case4` + `kubectl get svc case4 -o yaml` | `targetPort: 8080` alors que l'appli écoute sur 8000 | `targetPort: 8000` (ou un port nommé) |
| 5 | `OOMKilled` puis `CrashLoopBackOff` | `describe pod` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137` | limite mémoire 24Mi < besoin réel (~70 Mi) | limite ≥ 128Mi |
| 6 | `Pending` indéfiniment | `describe pod` → `0/3 nodes are available: 3 Insufficient cpu` | request CPU de 24 cœurs | request réaliste (`50m`) |
| 7 | Redémarrages en boucle (`RESTARTS` qui monte) | `describe pod` → `Liveness probe failed: HTTP probe failed with statuscode: 404` | chemin `/health` inexistant | `/healthz` |

Nettoyage : `kubectl delete ns debug-lab`.
