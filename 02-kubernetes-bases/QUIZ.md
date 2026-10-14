# Module 02 — Quiz Kubernetes (bases)

<details><summary>1. Décris ce qui se passe entre <code>kubectl apply -f deployment.yaml</code> et un pod Running.</summary>

kubectl → API server (authn, RBAC, admission mutating/validating, validation) → persistance dans etcd. Le contrôleur Deployment (kube-controller-manager) crée un ReplicaSet ; le contrôleur ReplicaSet crée les Pods (Pending, sans nœud). Le scheduler filtre/score les nœuds et assigne `nodeName`. Le kubelet du nœud voit le pod, demande au runtime (containerd via CRI) de tirer l'image et démarrer les conteneurs, le CNI configure le réseau/IP. Le kubelet lance les probes et met à jour le status ; une fois Ready, le pod est ajouté aux EndpointSlices des Services qui le sélectionnent.
</details>

<details><summary>2. Quel est le seul composant qui parle à etcd ? Pourquoi est-ce important ?</summary>

L'API server. Tout passe par lui : authentification, autorisation, admission, validation, audit. Les contrôleurs, le scheduler et les kubelets ne font que des watch/update via l'API. etcd contient tout l'état (y compris les Secrets) : il faut le sauvegarder (snapshots), le chiffrer au repos, et en restreindre l'accès réseau.
</details>

<details><summary>3. Différence entre un Deployment et un ReplicaSet ? Pourquoi ne crée-t-on jamais de ReplicaSet directement ?</summary>

Le ReplicaSet maintient N pods identiques. Le Deployment gère plusieurs ReplicaSets dans le temps pour orchestrer les mises à jour (rolling update), l'historique des révisions et les rollbacks. Un ReplicaSet seul ne sait pas mettre à jour ses pods existants quand on change le template.
</details>

<details><summary>4. Un rollout avec <code>maxSurge: 1, maxUnavailable: 0</code> et une nouvelle version dont la readiness ne passe jamais : que se passe-t-il ?</summary>

Kubernetes crée 1 nouveau pod en surplus ; il ne devient jamais Ready, donc aucun ancien pod n'est supprimé (maxUnavailable 0). Le rollout reste bloqué, l'ancienne version sert toujours 100 % du trafic. Après `progressDeadlineSeconds` (600 s par défaut), le Deployment passe en condition `Progressing=False` (ProgressDeadlineExceeded) ; Kubernetes ne fait pas de rollback automatique (Argo Rollouts ou la CI peuvent le faire).
</details>

<details><summary>5. Liveness, readiness, startup : différences et erreurs classiques ?</summary>

Startup : protège les applis lentes à démarrer (désactive les autres probes tant qu'elle n'a pas réussi). Liveness : échec → redémarrage du conteneur. Readiness : échec → retrait du trafic (endpoints), sans redémarrage. Erreurs : tester une dépendance externe dans la liveness (redémarrages en cascade), timeouts trop courts (redémarrages sous charge), même endpoint pour liveness et readiness, absence de readiness (trafic envoyé à un pod pas prêt pendant le rollout).
</details>

<details><summary>6. Requests vs limits ? Que se passe-t-il quand on dépasse chacune pour le CPU et la mémoire ?</summary>

Requests : quantité réservée, utilisée par le scheduler pour placer le pod (et pour les priorités CPU via les poids cgroup). Limits : plafond imposé par le cgroup. CPU au-delà de la limite → throttling (ralentissement). Mémoire au-delà de la limite → OOMKilled (exit 137) et redémarrage. Dépasser sa request mémoire sans limite atteinte est permis mais rend le pod candidat à l'éviction si le nœud manque de mémoire.
</details>

<details><summary>7. Quelles sont les classes QoS et comment sont-elles déterminées ?</summary>

Guaranteed (requests = limits pour CPU et mémoire sur tous les conteneurs), Burstable (au moins une request/limit, sans être Guaranteed), BestEffort (rien). En cas de pression mémoire, le kubelet évince d'abord les BestEffort, puis les Burstable qui dépassent leurs requests, et les Guaranteed en dernier.
</details>

<details><summary>8. Un Service n'a aucun endpoint. Quelles sont les causes possibles ?</summary>

Le sélecteur du Service ne correspond pas aux labels des pods (faute de frappe, mauvais label), les pods ne sont pas Ready (readiness en échec), aucun pod n'existe (Deployment à 0, Pending, erreur de création), ou mauvais namespace. Diagnostic : `kubectl get endpointslices -l kubernetes.io/service-name=X`, comparer `kubectl get svc X -o yaml` (selector) avec `kubectl get pods --show-labels`.
</details>

<details><summary>9. Comment un pod résout-il <code>postgres</code> et atteint-il le bon pod ?</summary>

Le `/etc/resolv.conf` du pod pointe vers CoreDNS avec des domaines de recherche (`<ns>.svc.cluster.local`, `svc.cluster.local`, `cluster.local`). `postgres` est résolu en ClusterIP du Service `postgres` du même namespace. Cette IP virtuelle n'existe sur aucune interface : kube-proxy a programmé des règles iptables/IPVS/nftables sur chaque nœud qui la traduisent (DNAT) vers l'IP:port d'un des endpoints Ready.
</details>

<details><summary>10. Un Secret Kubernetes est-il sécurisé ?</summary>

Pas en soi : c'est du base64 (encodage). La sécurité repose sur le RBAC (qui peut `get secrets`), le chiffrement au repos d'etcd (EncryptionConfiguration, idéalement avec un KMS), l'absence de Secrets en clair dans Git (Sealed Secrets, SOPS, External Secrets + Vault/cloud secret manager), et le fait de monter les secrets en fichiers plutôt qu'en variables d'env (qui fuient plus facilement dans les logs/dumps).
</details>

<details><summary>11. J'ai modifié un ConfigMap mais mon appli ne voit pas le changement. Pourquoi et comment corriger ?</summary>

Les variables d'environnement sont injectées au démarrage du conteneur. Il faut redémarrer les pods (`kubectl rollout restart`). Mieux : nommer le ConfigMap avec un hash de son contenu (configMapGenerator Kustomize, checksum annotation Helm) pour que tout changement modifie le template du pod et déclenche automatiquement un rollout. Les ConfigMaps montés en volume (hors subPath) sont, eux, mis à jour dans le pod après quelques dizaines de secondes, mais l'appli doit relire le fichier.
</details>

<details><summary>12. Un pod est Pending. Ta démarche ?</summary>

`kubectl describe pod` et lire les Events du scheduler : ressources insuffisantes (requests trop élevées / cluster plein), taint non tolérée, nodeSelector/affinité impossible, PVC non lié (pas de StorageClass, mauvais accessMode/zone), quota de namespace atteint (dans ce cas le pod n'est même pas créé : voir les events du ReplicaSet).
</details>

<details><summary>13. Différence entre taints/tolerations et node affinity ?</summary>

L'affinité est portée par le pod et l'attire vers des nœuds. La taint est portée par le nœud et repousse les pods ; une toleration autorise un pod à y aller (sans l'y obliger). Pour réserver des nœuds (GPU) à certains pods, on combine les deux : taint sur le nœud (repousse les autres) + toleration et affinité sur les pods concernés (les y envoie).
</details>

<details><summary>14. Pourquoi <code>kubectl apply</code> plutôt que <code>create</code> ?</summary>

`apply` est déclaratif et idempotent : il calcule la différence entre le manifeste, la dernière configuration appliquée et l'état live (fusion à 3 voies, ou server-side apply avec gestion des « field managers ») et ne modifie que ce qui a changé. `create` échoue si l'objet existe. Le mode déclaratif est la base de GitOps : les fichiers sont la source de vérité.
</details>

<details><summary>15. Qu'est-ce qu'un pod statique ? Où en as-tu vu ?</summary>

Un pod défini par un fichier dans `/etc/kubernetes/manifests` d'un nœud, lancé directement par le kubelet sans passer par le scheduler (le kubelet crée un « mirror pod » visible dans l'API). C'est ainsi que kubeadm (donc kind) fait tourner le control plane : etcd, kube-apiserver, controller-manager, scheduler.
</details>
