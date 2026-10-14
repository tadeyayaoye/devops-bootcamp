# Module 03 — Quiz Kubernetes avancé

<details><summary>1. Pourquoi Gateway API plutôt qu'Ingress aujourd'hui ?</summary>

Ingress mélange les responsabilités (infra et applicatif dans un seul objet) et repose sur des annotations propriétaires pour tout ce qui dépasse host/path. Gateway API sépare les rôles (GatewayClass pour l'infra, Gateway pour la plateforme, HTTPRoute pour les équipes applicatives dans leur namespace), standardise les fonctions avancées (poids pour le canary, headers, réécritures, timeouts, multi-protocole) et est portable entre implémentations. Et ingress-nginx, le contrôleur le plus répandu, a été retiré en mars 2026.
</details>

<details><summary>2. Deployment ou StatefulSet pour une base de données ? Le StatefulSet suffit-il ?</summary>

StatefulSet : identité stable (postgres-0), un PVC par réplica qui suit le pod, DNS par pod via un Service headless, ordre de démarrage. Mais il ne gère ni la réplication, ni le failover, ni les sauvegardes/PITR, ni les upgrades majeurs : il faut un opérateur (CloudNativePG…) ou un service managé, ce qui est souvent le meilleur choix en entreprise.
</details>

<details><summary>3. Que se passe-t-il pour le PVC quand on supprime le StatefulSet ? Et quand on supprime le PVC ?</summary>

Par défaut, supprimer le StatefulSet ne supprime pas les PVC (protection des données ; configurable via `persistentVolumeClaimRetentionPolicy`). Supprimer le PVC libère le PV, qui est alors supprimé ou conservé selon la `reclaimPolicy` de la StorageClass (`Delete` par défaut sur la plupart des classes dynamiques, `Retain` conseillé pour des données critiques).
</details>

<details><summary>4. Comment l'HPA calcule-t-il le nombre de réplicas ? Pourquoi affiche-t-il parfois <code>&lt;unknown&gt;</code> ?</summary>

`désirés = ceil(actuels × métrique_actuelle / cible)`, l'utilisation CPU étant exprimée en % de la request. `<unknown>` : metrics-server absent/en erreur, pods sans request CPU, ou pods pas encore prêts/sans métriques. Il applique aussi des fenêtres de stabilisation (scale down prudent par défaut : 5 min).
</details>

<details><summary>5. HPA et champ <code>replicas</code> dans le manifeste versionné : quel conflit ?</summary>

L'HPA modifie `spec.replicas` du Deployment. Si le manifeste versionné le fixe, chaque `apply` (ou synchro Argo CD) le remet à la valeur du fichier, provoquant des yo-yo. Solution : ne pas définir `replicas` quand un HPA est présent, ou dire à Argo CD d'ignorer ce champ (`ignoreDifferences`).
</details>

<details><summary>6. À quoi sert un PodDisruptionBudget ? Protège-t-il d'un crash de nœud ?</summary>

Il limite les interruptions volontaires (drain pour maintenance, upgrade de nœuds, Cluster Autoscaler qui retire un nœud) : l'éviction est refusée si elle ferait passer sous `minAvailable`. Il ne protège pas des pannes involontaires (crash de nœud, OOM) : pour ça, plusieurs réplicas répartis (topologySpread/anti-affinité).
</details>

<details><summary>7. Explique Role, ClusterRole, RoleBinding, ClusterRoleBinding.</summary>

Role : permissions (verbes × ressources × apiGroups) dans un namespace. ClusterRole : idem mais cluster-wide ou pour des ressources non namespacées (nodes, PV), ou comme modèle réutilisable. RoleBinding : attribue un Role (ou une ClusterRole, restreinte alors au namespace du binding) à des sujets dans un namespace. ClusterRoleBinding : attribue une ClusterRole sur tout le cluster. Les sujets : User, Group (fournis par l'authentification : certificats, OIDC) et ServiceAccount.
</details>

<details><summary>8. Qu'impose le profil Pod Security <code>restricted</code> ? Comment l'active-t-on ?</summary>

Non-root (`runAsNonRoot`), pas d'escalade de privilèges, drop de toutes les capabilities (sauf NET_BIND_SERVICE autorisée), seccomp RuntimeDefault ou Localhost, types de volumes limités, pas de hostNetwork/hostPID/hostPath ni privileged. On l'active par labels sur le namespace : `pod-security.kubernetes.io/enforce: restricted` (refus), `warn`, `audit`.
</details>

<details><summary>9. Je pose une NetworkPolicy default-deny en ingress : les probes du kubelet échouent-elles ? Et Prometheus ?</summary>

Les probes viennent du kubelet du nœud lui-même ; la plupart des CNI les autorisent implicitement (le trafic du nœud vers ses pods n'est pas filtré). Prometheus, lui, est un pod d'un autre namespace : il faut l'autoriser explicitement, sinon les cibles passent DOWN. Si on bloque aussi l'egress, il faut autoriser le DNS (kube-system:53) sinon plus aucune résolution ne fonctionne.
</details>

<details><summary>10. Dans une règle <code>from</code>, quelle différence entre deux éléments séparés et un namespaceSelector + podSelector dans le même élément ?</summary>

Deux éléments de liste = OU (pods qui matchent le podSelector dans le namespace de la policy, OU tous les pods des namespaces sélectionnés). Les deux sélecteurs dans le même élément = ET (les pods correspondant au podSelector, dans les namespaces correspondant au namespaceSelector). Une indentation de différence change complètement la sécurité.
</details>

<details><summary>11. Helm : chart, release, values, revision ? Où Helm stocke-t-il l'état ?</summary>

Chart = paquet de templates + valeurs par défaut. Values = paramètres. Release = instance installée d'un chart avec un nom dans un namespace. Revision = chaque install/upgrade/rollback incrémente la révision. L'état (manifeste rendu, values, statut) est stocké dans des Secrets `sh.helm.release.v1.<release>.v<rev>` dans le namespace de la release.
</details>

<details><summary>12. Pourquoi l'annotation <code>checksum/config</code> dans un template de Deployment ?</summary>

Les pods ne relisent pas un ConfigMap injecté en variables d'environnement. En mettant le hash du ConfigMap rendu dans une annotation du template de pod, toute modification de configuration modifie le template, donc déclenche un nouveau ReplicaSet et un rolling update automatique. Kustomize obtient le même effet avec le suffixe de hash du configMapGenerator.
</details>

<details><summary>13. Pièges connus avec les CRD dans Helm ?</summary>

Les CRD du dossier `crds/` sont installées au premier install mais jamais mises à jour ni supprimées par Helm (pour éviter de perdre des ressources custom). Il faut les mettre à jour à part (kubectl apply --server-side, chart dédié aux CRD, ou option du chart). Les très grosses CRD dépassent aussi la limite de l'annotation `last-applied-configuration` → `--server-side` (Argo CD : `ServerSideApply=true`).
</details>

<details><summary>14. Helm ou Kustomize : comment choisis-tu ?</summary>

Helm pour distribuer/installer un logiciel paramétrable (charts tiers, ou une appli maison partagée par beaucoup d'équipes), avec gestion de release et rollback. Kustomize pour décliner ses propres manifests par environnement avec du YAML pur, lisible et diffable, sans logique de template. Les deux se combinent : Helm pour la plateforme, Kustomize pour les applis, et Argo CD sait rendre les deux.
</details>

<details><summary>15. Qu'est-ce qu'un opérateur Kubernetes ?</summary>

Un contrôleur personnalisé qui gère un type de ressource défini par une CRD, en encodant le savoir-faire d'exploitation (installation, configuration, sauvegarde, failover, upgrade) dans une boucle de réconciliation. Exemples : Prometheus Operator (ServiceMonitor), CloudNativePG (Cluster), cert-manager (Certificate), Argo CD (Application).
</details>
