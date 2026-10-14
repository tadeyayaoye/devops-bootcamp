# Runbooks taskapi

> Un **runbook** est la procédure à suivre quand une alerte sonne : il est lié à l'alerte (`runbook_url`) pour que la personne d'astreinte, réveillée à 3 h du matin, sache **quoi vérifier et quoi faire** sans réfléchir à partir de zéro.

---

## TaskapiDown

**Signification** : Prometheus n'arrive à scraper aucune instance de taskapi dans le namespace.

**Impact** : l'API est probablement indisponible pour les utilisateurs de cet environnement.

**Diagnostic**

```bash
NS=taskapi-prod
kubectl -n $NS get pods -l app.kubernetes.io/name=taskapi
kubectl -n $NS describe pod -l app.kubernetes.io/name=taskapi | sed -n '/Events/,$p'
kubectl -n $NS logs -l app.kubernetes.io/name=taskapi --tail=50 --prefix
argocd app get taskapi-${NS#taskapi-}                         # un déploiement récent ? Degraded ?
kubectl -n monitoring port-forward svc/kps-prometheus 9090 &   # puis Status → Targets : erreur de scrape ?
```

**Causes fréquentes** : pods en CrashLoopBackOff (config, secret, base), mauvais déploiement récent, NetworkPolicy qui bloque `monitoring`, Service/ServiceMonitor modifié (labels, nom de port).

**Remédiation** : si un déploiement récent est en cause → **rollback GitOps** (`git revert` du commit de promotion). Sinon corriger la cause et suivre la reprise dans Grafana.

---

## TaskapiHighErrorRate

**Signification** : plus de 5 % des requêtes renvoient une erreur 5xx depuis 2 minutes.

**Diagnostic**

1. Dashboard **taskapi — RED** : quelles routes ? depuis quand ? corrélé à un déploiement (annotations, historique Argo CD) ?
2. Logs d'erreur : dans Grafana → Explore → Loki : `{namespace="taskapi-prod", app="taskapi"} | json | level="error"` (module 10).
3. Base de données : `kubectl -n taskapi-prod get pods -l app.kubernetes.io/name=postgres`, `/readyz` des pods.
4. Chaos activé par erreur ? `curl -s http://taskapi.localhost/chaos`.

**Remédiation** : rollback si lié à un déploiement ; désactiver le chaos (`PUT /chaos {"error_rate":0}`) ; scaler/réparer la dépendance en cause.

---

## TaskapiHighLatency

**Signification** : le p95 de la latence dépasse 500 ms depuis 5 minutes.

**Diagnostic** : saturation (CPU des pods, HPA au maximum ? `kubectl -n $NS get hpa`), lenteur de la base, latence injectée par le chaos, une route particulière (panneau « Trafic par route »). Au module 10 : ouvrir une **trace** lente dans Tempo pour voir quel span consomme le temps.

**Remédiation** : augmenter `maxReplicas`/les ressources si saturation, corriger la requête lente, désactiver le chaos.

---

## TaskapiPodRestarting

**Diagnostic** : `kubectl -n $NS describe pod <pod>` → `Last State: Terminated, Reason: OOMKilled` (limite mémoire), `Error` (crash : `kubectl logs --previous`), ou liveness en échec (événements `Unhealthy`).
