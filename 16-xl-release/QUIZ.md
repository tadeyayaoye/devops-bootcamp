# Module 16 — Quiz XL Release

<details><summary>1. Quelle différence entre un pipeline CI/CD et un orchestrateur de release ?</summary>

Le pipeline construit, teste et déploie automatiquement une application. L'orchestrateur de release modélise tout le processus de mise en production : étapes humaines (validations, CAB, tests manuels), plusieurs outils (ITSM, CI, déploiement, ordonnanceur, supervision), plusieurs applications à livrer ensemble, règles (gel, séparation des tâches) et traçabilité d'audit. Il appelle les pipelines, il ne les remplace pas.
</details>

<details><summary>2. Template, release, phase, task, gate ?</summary>

Le template est le modèle réutilisable d'un processus de MEP ; une release est une exécution de ce template avec ses variables. Une phase est une grande étape séquentielle ; une task est une action (manuelle, automatique, notification, script, appel d'outil) ; une gate est un point de contrôle bloquant (conditions, approbations, dépendances vers d'autres releases) qui matérialise le go/no-go.
</details>

<details><summary>3. Comment XL Release aide-t-il à respecter la séparation des tâches ?</summary>

Par les équipes et permissions au niveau des folders et des tâches : les développeurs peuvent démarrer une release et réaliser leurs tâches, mais seules les personnes de l'équipe d'approbation peuvent valider la gate de production. Chaque action est enregistrée (qui, quand, commentaire), ce qui produit la preuve d'audit.
</details>

<details><summary>4. Que se passe-t-il quand une tâche échoue, et pourquoi le « Skip » exige-t-il un commentaire ?</summary>

La release passe en échec ; on peut relancer la tâche (Retry), la sauter (Skip), la réassigner ou abandonner la release (Abort). Sauter une étape d'un processus contrôlé est une décision qui doit être justifiée et tracée pour l'audit : le commentaire documente qui a pris la décision et pourquoi.
</details>

<details><summary>5. Qu'est-ce qu'une blackout period ?</summary>

Une période de gel des mises en production définie dans le calendrier des releases (fin d'année, arrêté comptable, événement commercial). Les releases planifiées dans cette période sont signalées ou bloquées, ce qui fait respecter automatiquement la règle de gel.
</details>

<details><summary>6. Comment versionner les processus de MEP ?</summary>

Avec « Release as code » : exporter templates, folders et configurations en YAML, les stocker dans Git, les faire revoir en PR, et les appliquer avec le CLI `xl apply`. Les secrets restent dans les variables de type password ou les connexions, pas dans le YAML.
</details>

<details><summary>7. Comment XL Release et Argo CD (GitOps) peuvent-ils cohabiter ?</summary>

Argo CD réalise le déploiement (réconciliation de l'état désiré décrit dans Git). XL Release orchestre le processus autour : approbations CAB, communication, maintenance de supervision, suspension du batch, coordination multi-applications, et déclenche la promotion GitOps (création/merge de la PR `envs/prod`) au bon moment, puis vérifie le résultat.
</details>

<details><summary>8. Comment la CI peut-elle démarrer une release ?</summary>

Par l'API REST de XL Release (`POST /api/v1/templates/<id>/start` avec titre et variables), par un trigger configuré dans XL Release, ou par un plugin. La CI utilise un compte technique dédié aux droits limités, stocké dans son coffre de credentials.
</details>

<details><summary>9. Pourquoi éviter un template entièrement composé de tâches manuelles ?</summary>

On obtient une checklist coûteuse, lente et sujette à l'erreur humaine, sans les bénéfices de l'automatisation. L'humain doit intervenir pour les décisions (go/no-go, validation métier) ; tout ce qui est vérifiable ou exécutable automatiquement (build, tests, déploiement, contrôles de santé, maintenances, notifications) doit l'être.
</details>

<details><summary>10. XL Release et XL Deploy : quelle différence ?</summary>

XL Release (Digital.ai Release) orchestre le processus de release de bout en bout. XL Deploy (Digital.ai Deploy) automatise le déploiement technique d'un package applicatif vers des environnements (modèle package/environnement/dictionnaires). XL Release appelle souvent XL Deploy comme l'une de ses tâches.
</details>
