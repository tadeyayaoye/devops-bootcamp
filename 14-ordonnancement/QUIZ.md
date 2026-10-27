# Module 14 — Quiz ordonnancement et Control-M

<details><summary>1. Pourquoi un ordonnanceur plutôt que cron ?</summary>

cron déclenche une commande à heure fixe sur une machine. Un ordonnanceur gère les dépendances (séquences, conditions inter-chaînes, fichiers), les ressources partagées, les calendriers métier, la date d'ordonnancement, l'exécution centralisée sur de nombreux serveurs via des agents, la supervision en temps réel du plan de production, la reprise (rerun, set to OK), les SLA, les droits et l'audit.
</details>

<details><summary>2. Qu'est-ce que l'ODATE ? Pourquoi ne pas utiliser la date système ?</summary>

La date d'ordonnancement (date métier traitée par l'exécution), attribuée au moment où le job entre dans le plan. Un traitement de l'arrêté du 27 qui tourne à 2 h le 28, ou qui est relancé 3 jours plus tard, doit traiter les données du 27 : la date système donnerait un résultat faux. Dans Control-M : `%%ODATE` (AAMMJJ) et `%%$ODATE` (AAAAMMJJ).
</details>

<details><summary>3. Décris l'architecture de Control-M.</summary>

Control-M/Enterprise Manager (point central : définitions, interface, sécurité, audit, Automation API) ; un ou plusieurs Control-M/Server (moteur d'un datacenter qui gère le plan actif et décide des lancements) ; des Agents sur chaque serveur d'exécution (Linux, Windows, AIX…) qui lancent les jobs et renvoient résultats et sysout ; des plug-ins pour les types de jobs spécialisés (SAP, bases, MFT, cloud, Kubernetes) ; Control-M for z/OS pour le mainframe.
</details>

<details><summary>4. Que se passe-t-il au « New Day » ?</summary>

À l'heure de bascule de la journée de production, Control-M/Server évalue les règles de planification (jours, calendriers) de chaque job/folder pour la nouvelle date d'ordonnancement et ordonnance ceux qui doivent tourner dans le plan actif (Active Jobs). Les jobs de la veille sont nettoyés ou conservés selon leurs paramètres.
</details>

<details><summary>5. Conditions et ressources : quelle différence ?</summary>

Une condition (événement daté, in/out) exprime une dépendance logique : « B attend que A ait posé ARRETE-OK du jour ». Une ressource limite la concurrence : une ressource quantitative (sémaphore) autorise N jobs simultanés ; une ressource de contrôle (mutex) donne un accès exclusif ou partagé. Une condition dit *quand*, une ressource dit *combien en même temps*.
</details>

<details><summary>6. Rerun, Set to OK, Hold, Kill : quand utiliser chacun ?</summary>

Rerun : relancer un job en échec après correction de la cause. Set to OK : forcer l'état OK sans réexécuter (le traitement a été fait autrement, ou l'échec est sans conséquence) — à tracer. Hold : empêcher un job de démarrer (maintenance, incident en amont). Kill : arrêter un job en cours (bloqué, ou dangereux).
</details>

<details><summary>7. Pourquoi l'idempotence des jobs est-elle cruciale en batch ?</summary>

Les relances sont fréquentes (pannes, fichiers corrigés, rattrapages). Un job idempotent peut être relancé sans dupliquer ni corrompre les données (il nettoie avant d'écrire, ou remplace de manière atomique). Cela simplifie les consignes de pilotage et réduit le risque d'erreur humaine la nuit.
</details>

<details><summary>8. Comment éviter qu'un file watcher démarre sur un fichier incomplet ?</summary>

Le producteur écrit sous un nom temporaire puis renomme (le renommage est atomique sur un même système de fichiers), ou dépose un fichier témoin (.ok/.done) après le fichier de données ; côté watcher, on peut aussi exiger une taille minimale ou une taille stable pendant un délai. Ensuite, un contrôle (trailer, totaux, empreinte) valide le contenu.
</details>

<details><summary>9. Qu'est-ce que le Jobs-as-Code chez Control-M ?</summary>

Les définitions de jobs et folders sont écrites en JSON (ou Python) et versionnées dans Git. Le CLI `ctm` (Automation API REST) les valide (`ctm build`), les exécute pour test (`ctm run`) et les déploie (`ctm deploy`), avec des deploy descriptors pour adapter les valeurs par environnement. On peut ainsi les intégrer à une CI/CD avec revue de code, comme le reste de l'infrastructure.
</details>

<details><summary>10. Fais la correspondance Airflow ↔ Control-M pour : DAG, logical date, pool, sensor, clear, mark success, asset.</summary>

DAG ↔ Folder ; logical date ↔ ODATE ; pool ↔ ressource quantitative ; FileSensor ↔ File Watcher ; Clear ↔ Rerun ; Mark success ↔ Set to OK ; Asset (outlets / schedule) ↔ conditions (AddEvents / WaitForEvents).
</details>

<details><summary>11. Pourquoi les banques gardent-elles Control-M plutôt qu'Airflow pour la production ?</summary>

Agents sur toutes les plateformes (dont AIX et mainframe), plan de production journalier et pilotage de nuit adaptés aux opérateurs, calendriers et conditions datées natifs, SLA management, MFT intégré, sécurité et audit éprouvés, support éditeur, et des dizaines de milliers de jobs existants. Airflow est excellent pour les pipelines de données et l'orchestration « as code », et Control-M sait d'ailleurs piloter des DAGs Airflow.
</details>

<details><summary>12. Que faire si un job d'attente de fichier atteint son timeout à 2 h du matin ?</summary>

Suivre la consigne de pilotage : vérifier si le fichier est arrivé sous un autre nom ou dans un autre répertoire, vérifier le flux de transfert (MFT), contacter l'astreinte du partenaire selon la procédure, informer l'astreinte applicative ; quand le fichier est là, relancer le watcher (Rerun) pour que la chaîne reprenne. Ne jamais forcer OK un job d'attente : la suite traiterait un fichier absent.
</details>
