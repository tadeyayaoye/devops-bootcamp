# Module 08 — Quiz GitOps et Argo CD

<details><summary>1. Quels sont les principes du GitOps ?</summary>

(OpenGitOps) 1. L'état désiré est déclaratif. 2. Il est versionné et immuable (Git, historique complet). 3. Il est récupéré automatiquement par des agents (pull). 4. Il est réconcilié en continu (les écarts sont détectés et corrigés).
</details>

<details><summary>2. Pourquoi le modèle « pull » est-il plus sûr que le « push » depuis la CI ?</summary>

La CI n'a plus besoin d'identifiants du cluster ni d'accès réseau à son API : elle n'a qu'un droit d'écriture sur un repo Git. L'agent (Argo CD) est dans le cluster, avec des droits locaux. La surface d'attaque diminue (une CI compromise ne donne pas directement le cluster), et toute modification passe par Git (audit, revue).
</details>

<details><summary>3. Sync status vs health status ?</summary>

Sync : le live correspond-il à ce qui est dans Git (Synced/OutOfSync) ? Health : les ressources fonctionnent-elles (Healthy/Progressing/Degraded/Missing/Suspended) selon des règles par type. Une app peut être Synced mais Degraded (manifeste appliqué, mais pods en CrashLoop), ou OutOfSync mais Healthy (dérive manuelle qui fonctionne).
</details>

<details><summary>4. Que font <code>prune</code> et <code>selfHeal</code> ?</summary>

`prune` : supprime du cluster les ressources qui ont été retirées de Git (sinon elles restent, orphelines). `selfHeal` : lorsqu'une ressource est modifiée hors Git (kubectl edit), Argo CD la remet dans l'état de Git automatiquement. Sans selfHeal, l'app est seulement marquée OutOfSync.
</details>

<details><summary>5. Comment fais-tu un rollback en GitOps ?</summary>

`git revert` du commit (ou de la PR) qui a introduit la version fautive : Git reste la source de vérité et Argo CD resynchronise l'ancienne version, avec une trace dans l'historique. `argocd app rollback` est possible en urgence mais désactive l'auto-sync et crée un écart avec Git qu'il faut ensuite reporter.
</details>

<details><summary>6. App of apps ou ApplicationSet ?</summary>

App of apps : une Application racine qui déploie un dossier d'Applications écrites à la main — idéal pour amorcer un cluster (bootstrap) et regrouper la plateforme. ApplicationSet : génère des Applications à partir d'un template et de générateurs (dossiers Git, liste, clusters, PR, matrix) — idéal pour décliner la même app sur N environnements/clusters ou créer des environnements éphémères. On combine souvent les deux (la racine déploie des ApplicationSets).
</details>

<details><summary>7. Comment gérer des secrets dans un repo GitOps ?</summary>

Jamais en clair. Options : Sealed Secrets (chiffrement asymétrique, seul le contrôleur du cluster déchiffre), SOPS (fichiers chiffrés avec age/KMS, déchiffrés au rendu), External Secrets Operator (Git contient une référence ; la valeur vient de Vault/AWS SM/Azure KV/GCP SM), ou injection runtime (Vault Agent, CSI). En entreprise, ESO + coffre centralisé est le plus courant (rotation, audit).
</details>

<details><summary>8. Que se passe-t-il si tu recrées le cluster sans avoir sauvegardé la clé de Sealed Secrets ?</summary>

Le nouveau contrôleur génère une nouvelle paire de clés : il ne peut pas déchiffrer les SealedSecret existants dans Git, les Secrets ne sont pas créés et les pods qui en dépendent restent en CreateContainerConfigError. Il faut restaurer la clé sauvegardée (avant le démarrage du contrôleur) ou re-sceller tous les secrets avec la nouvelle clé publique.
</details>

<details><summary>9. Comment promouvoir une version de dev à prod en GitOps ?</summary>

Modifier le tag d'image (ou la version de chart) dans le dossier de l'environnement prod, par Pull Request : la revue de la PR fait office d'approbation de mise en production. C'est la même image (même digest) que celle validée en dev : aucun rebuild. Automatisable (script, Argo CD Image Updater, Kargo, Renovate) en gardant la PR comme point de contrôle.
</details>

<details><summary>10. Pourquoi un dossier par environnement plutôt qu'une branche par environnement ?</summary>

Avec des branches, les différences entre environnements sont cachées dans l'historique, les merges dans un sens puis dans l'autre créent des conflits et des divergences involontaires, et il est difficile de voir l'état de tous les envs d'un coup d'œil. Avec des dossiers sur une seule branche, les différences sont explicites (overlays), comparables par diff, et une promotion est un changement simple et lisible.
</details>

<details><summary>11. À quoi servent les sync waves et les hooks ?</summary>

Les vagues ordonnent l'application des ressources dans un sync (Argo attend que la vague précédente soit saine) : CRD et projets, puis contrôleurs, puis base de données, puis application. Les hooks exécutent des Jobs à des moments précis : PreSync (migration de schéma), PostSync (tests de fumée, notification), SyncFail (alerte, nettoyage).
</details>

<details><summary>12. Comment éviter qu'Argo CD et un HPA se battent sur le nombre de réplicas ?</summary>

Ne pas définir `spec.replicas` dans le Deployment versionné (l'HPA en est le seul propriétaire) et/ou configurer `ignoreDifferences` sur `/spec/replicas` (avec `RespectIgnoreDifferences=true` si besoin), éventuellement globalement dans `argocd-cm`.
</details>

<details><summary>13. Argo CD ou Flux ?</summary>

Les deux sont des projets CNCF graduated et fiables. Argo CD : UI riche, modèle centralisé (une instance pilote plusieurs clusters), AppProjects pour le multi-équipe, ApplicationSets. Flux : ensemble de contrôleurs Kubernetes natifs par cluster, SOPS intégré, pas d'UI native, très « Kubernetes-like ». Le choix dépend de l'organisation ; Argo CD est plus répandu.
</details>
