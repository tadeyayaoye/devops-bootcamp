# Module 06 — Quiz CI/CD et Jenkins

<details><summary>1. Différence entre intégration continue, livraison continue et déploiement continu ?</summary>

CI : chaque changement est intégré fréquemment à la branche principale et validé automatiquement (build, tests, analyses). Livraison continue : chaque changement validé produit un artefact prêt à partir en production, la mise en prod restant une décision manuelle. Déploiement continu : la mise en production est elle-même automatique dès que le pipeline est vert.
</details>

<details><summary>2. Que signifie « build once, deploy many » ?</summary>

L'artefact (image Docker, binaire) est construit une seule fois en CI, identifié de façon immuable (SHA/digest), puis c'est exactement ce même artefact qui est promu en dev, staging et prod, seule la configuration change. Reconstruire pour chaque environnement introduirait des différences (dépendances téléchargées à un autre moment, outils différents) et casserait la traçabilité.
</details>

<details><summary>3. Pourquoi ne pas exécuter de builds sur le contrôleur Jenkins ?</summary>

Sécurité (un build a accès au JENKINS_HOME : credentials, configuration de tous les jobs), stabilité (un build gourmand dégrade l'UI et la planification), et reproductibilité (les outils installés sur le contrôleur deviennent des dépendances cachées). On met `numExecutors: 0` et on utilise des agents, idéalement éphémères (Docker, pods Kubernetes).
</details>

<details><summary>4. Comment rendre une instance Jenkins reproductible ?</summary>

Image Docker versionnée (version LTS + outils), plugins listés dans `plugins.txt` et installés au build, configuration globale en JCasC (YAML, secrets injectés par variables ou coffre), jobs en Job DSL ou découverts automatiquement (Multibranch/Organization Folder), pipelines en Jenkinsfile dans les repos, logique partagée en Shared Libraries. Il ne reste alors à sauvegarder que l'historique des builds et éventuellement des credentials non externalisés.
</details>

<details><summary>5. Pipeline déclaratif ou scripté ?</summary>

Déclaratif : syntaxe structurée (pipeline/agent/stages/steps/post), validée avant exécution, lisible, avec `when`, `options`, `parallel`, `matrix`, `post` intégrés : c'est le standard. Scripté : du Groovy libre, plus puissant mais plus difficile à maintenir ; utilisé dans des cas dynamiques ou à l'intérieur de Shared Libraries.
</details>

<details><summary>6. Comment un secret peut-il fuiter dans un Jenkinsfile, et comment l'éviter ?</summary>

Par interpolation Groovy : `sh "curl -u user:${TOKEN} …"` place le secret dans le script généré (visible dans les détails du build, l'historique des processus). Utiliser des guillemets simples pour que ce soit le shell qui lise la variable d'environnement (`sh 'curl -u "user:$TOKEN" …'`), limiter la portée avec `withCredentials`, ne jamais faire `echo`/`set -x` sur un secret. Jenkins masque les valeurs connues dans les logs, mais pas leurs transformations (base64, etc.).
</details>

<details><summary>7. Qu'apporte un job Multibranch ?</summary>

Découverte automatique des branches (et PR) contenant un Jenkinsfile : un sous-job par branche, créé et supprimé automatiquement, avec son propre historique. Chaque branche porte la définition de son pipeline (pipeline as code). Déclenchement par webhook ou scan périodique.
</details>

<details><summary>8. Docker-out-of-Docker, Docker-in-Docker, Kaniko : avantages et risques ?</summary>

DooD (socket de l'hôte monté) : simple et rapide (cache partagé), mais le conteneur Jenkins devient équivalent root sur l'hôte et les chemins de volumes sont ceux de l'hôte. DinD : démon séparé, mais conteneur `--privileged`. Kaniko/BuildKit rootless/Buildah : construction d'images sans démon ni privilèges, recommandé dans Kubernetes et les environnements multi-tenants.
</details>

<details><summary>9. Qu'est-ce qu'une Shared Library et pourquoi l'utiliser ?</summary>

Un repo de code Groovy (vars/, src/, resources/) chargé par les pipelines (`@Library('nom@version')`). Il factorise les étapes communes (build, scan, déploiement, notifications) de dizaines de pipelines, permet de faire évoluer les standards de façon centralisée et versionnée, et garde les Jenkinsfile courts.
</details>

<details><summary>10. Quelles sont les 4 métriques DORA ?</summary>

Fréquence de déploiement, délai de mise en production (lead time for changes, du commit à la prod), taux d'échec des changements (change failure rate) et temps de restauration du service (MTTR / failed deployment recovery time). Les deux premières mesurent la vitesse, les deux dernières la stabilité ; les équipes performantes excellent sur les quatre à la fois.
</details>

<details><summary>11. Ton pipeline met 40 minutes. Comment l'accélérer ?</summary>

Mesurer d'abord (durée par stage). Puis : paralléliser les étapes indépendantes, mettre en cache les dépendances (pip/npm/maven, couches Docker via cache registry), ordonner en fail-fast, découper les tests (unitaires à chaque commit, e2e plus tard ou en parallèle/shardés), ne reconstruire que ce qui a changé (monorepo : détection de chemins), agents plus puissants ou éphémères en nombre, images de build préparées avec les outils.
</details>

<details><summary>12. Polling ou webhook ?</summary>

Webhook : GitHub notifie Jenkins à chaque push → déclenchement immédiat, pas de charge inutile ; nécessite que Jenkins soit joignable (ou un relais comme smee.io, un tunnel, un proxy). Polling/scan périodique : Jenkins interroge Git régulièrement → latence et charge, mais fonctionne derrière un pare-feu (notre cas en local).
</details>
