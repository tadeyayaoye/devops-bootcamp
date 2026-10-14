# Questions transverses (scénarios et conception)

> Ce sont les questions d'entretien qui mélangent plusieurs technos. Réponds à voix haute (2-3 min), en structurant : **clarifier → options → choix argumenté → risques**. Les éléments de réponse sont des pistes, pas des vérités uniques.

<details><summary>1. « Le site est lent depuis ce matin. » Par où commences-tu ?</summary>

Qualifier : qui/quoi est impacté (toutes les routes ? une région ? un client ?), depuis quand, quoi a changé (déploiements, config, trafic, dépendances). Dashboards RED : latence p95/p99 par route, débit, erreurs ; USE des ressources (CPU throttling, mémoire, saturation des pools, base). Traces des requêtes lentes pour localiser le span coûteux. Logs autour des traces. Corréler avec l'historique Argo CD/des déploiements. Mitiger d'abord (rollback, scale) si l'impact est fort, puis cause racine.
</details>

<details><summary>2. Conçois la chaîne CI/CD d'une nouvelle application de zéro.</summary>

Trunk-based/GitHub Flow, PR obligatoires. CI : lint, tests unitaires, SAST, SCA, secrets, build de l'image multi-stage, scan de l'image, SBOM, signature, push avec tag SHA. CD : GitOps (repo de config, Argo CD), dev automatique, staging/prod par PR, déploiement progressif (canary avec analyse des métriques via Argo Rollouts) et rollback par revert. Secrets via External Secrets + coffre. Observabilité dès le jour 1 : métriques RED, logs structurés, traces OTel, SLO. Infra en Terraform, environnements reproductibles.
</details>

<details><summary>3. Un développeur a besoin d'un environnement de test par Pull Request. Comment faire ?</summary>

ApplicationSet avec générateur `pullRequest` (Argo CD) : pour chaque PR ouverte, une Application déploie l'image construite par la CI pour cette PR dans un namespace `pr-<numéro>` avec un hostname dédié ; fermée → supprimée. Attention aux coûts (quotas, TTL), aux données (base éphémère ou seed), aux secrets (pas les secrets de prod) et à la sécurité (PR de forks).
</details>

<details><summary>4. Comment gérerais-tu les secrets de bout en bout ?</summary>

Source de vérité unique (Vault, AWS Secrets Manager…), aucun secret dans Git (références External Secrets ou valeurs chiffrées SOPS/Sealed), CI authentifiée par OIDC (pas de secrets statiques), Kubernetes : RBAC strict, chiffrement d'etcd, montage en fichiers, rotation automatisée, audit des accès. Détection des fuites (gitleaks, push protection) et procédure de révocation.
</details>

<details><summary>5. Le cluster de prod est perdu. Combien de temps pour le reconstruire et qu'est-ce qui serait perdu ?</summary>

Avec IaC + GitOps : cluster (Terraform) + socle (Argo CD) + bootstrap = dizaines de minutes ; toutes les ressources reviennent depuis Git. Perdu sans précautions : données des volumes (bases, files), clés de Sealed Secrets, historique de métriques/logs locaux, ressources créées hors Git. D'où : bases managées ou sauvegardes externes (Velero, pg_dump vers stockage objet, PITR), clé de chiffrement sauvegardée dans un coffre, stockage objet pour Loki/Tempo/Thanos, exercices de restauration réguliers (une sauvegarde non testée n'existe pas).
</details>

<details><summary>6. Kubernetes est-il toujours la bonne réponse ?</summary>

Non. Pour une petite équipe avec quelques services : PaaS ou conteneurs managés (Cloud Run, ECS/Fargate, App Service, Fly.io) offrent déploiement, scaling, TLS, logs sans opérer de cluster. Kubernetes vaut son coût d'exploitation quand on a beaucoup de services, des besoins de portabilité/multi-cloud, une plateforme interne pour de nombreuses équipes, ou des besoins spécifiques (GPU, réseau, opérateurs). Le bon choix minimise la complexité pour le besoin réel.
</details>

<details><summary>7. Comment réduirais-tu le taux d'échec des changements ?</summary>

Plus petits changements plus fréquents, revue de code, tests automatisés pertinents (dont contrat/intégration), environnements de préprod fidèles (même IaC, même image), feature flags pour découpler déploiement et activation, déploiements progressifs avec analyse automatique et rollback, readiness probes sérieuses, quality gates, postmortems qui se traduisent en garde-fous.
</details>

<details><summary>8. Différence entre déploiement blue/green, canary et rolling update ?</summary>

Rolling : remplacement progressif des pods (natif Kubernetes) ; les deux versions coexistent ; rollback = nouveau rolling. Blue/green : deux environnements complets, bascule instantanée du trafic, rollback instantané, coût double pendant la bascule. Canary : une petite fraction du trafic va à la nouvelle version, on mesure (erreurs, latence) puis on augmente par paliers ou on annule — le plus sûr pour la prod (Argo Rollouts, Flagger, poids Gateway API).
</details>

<details><summary>9. On te demande de rendre une application « hautement disponible ». Que vérifies-tu ?</summary>

Plusieurs réplicas répartis sur nœuds/zones (topologySpread, anti-affinité), PDB, readiness/liveness correctes, arrêt gracieux (SIGTERM, preStop), pas d'état local (sessions externalisées), dépendances elles-mêmes HA (base répliquée/managée, cache), autoscaling, limites de ressources, plusieurs nœuds et zones côté cluster, tests de panne (chaos), et un SLO pour définir « disponible ».
</details>

<details><summary>10. Comment sécuriser une plateforme Kubernetes ?</summary>

Accès : SSO/OIDC, RBAC minimal, pas de cluster-admin partagé, audit logs. Workloads : Pod Security restricted, images signées et scannées, registres autorisés (Kyverno/Gatekeeper), NetworkPolicies default deny, pas de privilèges, secrets externes. Supply chain : CI durcie, actions épinglées, SBOM, provenance. Nœuds : OS minimal, mises à jour, CIS benchmark. Runtime : détection (Falco). Mises à jour régulières de Kubernetes et des composants.
</details>

<details><summary>11. Monorepo ou polyrepo ?</summary>

Monorepo : changements atomiques transverses, outillage et standards partagés, visibilité ; nécessite une CI capable de ne construire que ce qui change, et des droits plus fins. Polyrepo : autonomie et isolation des équipes, pipelines simples ; mais duplication, versions de librairies divergentes, changements transverses lourds. Dans tous les cas, séparer la configuration de déploiement (GitOps) du code applicatif est une bonne pratique.
</details>

<details><summary>12. Comment mesurer l'efficacité d'une équipe DevOps ?</summary>

Les métriques DORA (fréquence de déploiement, lead time, taux d'échec, temps de restauration), complétées par la fiabilité (respect des SLO, budget consommé), l'expérience développeur (temps de pipeline, temps pour obtenir un environnement), et la toil (travail manuel répétitif). Sans en faire des objectifs individuels (loi de Goodhart).
</details>

<details><summary>13. Ton pipeline CI met 45 minutes et les développeurs s'en plaignent. Plan d'action ?</summary>

Mesurer par étape, paralléliser, mettre en cache (dépendances, couches Docker, cache distant BuildKit), découper les tests (rapides sur chaque commit, lourds en nightly ou en parallèle/shardés), n'exécuter que l'impacté (monorepo), runners plus puissants ou éphémères en nombre, images de build préparées, et supprimer les étapes sans valeur. Objectif : feedback < 10 min sur les PR.
</details>

<details><summary>14. Une CVE critique est publiée sur une librairie très utilisée. Que fais-tu dans l'heure ?</summary>

Identifier l'exposition via les SBOM/scanners (quelles images, quels services, quels environnements), évaluer l'exploitabilité réelle et l'exposition (Internet ?), appliquer des mitigations immédiates (WAF, désactivation de fonctionnalité, NetworkPolicy), préparer les montées de version (Dependabot/Renovate), reconstruire et déployer via la chaîne normale (accélérée), vérifier le déploiement effectif partout, communiquer, documenter.
</details>

<details><summary>15. Explique la différence entre « configuration management » et « orchestration ».</summary>

La gestion de configuration (Ansible, Puppet) amène des machines existantes dans un état voulu (paquets, fichiers, services). L'orchestration (Kubernetes) gère le cycle de vie d'applications sur un ensemble de machines (placement, scaling, réparation, réseau de service) à partir d'un état désiré. Le provisioning (Terraform) crée les ressources elles-mêmes. GitOps applique le principe de réconciliation continue à la livraison.
</details>
