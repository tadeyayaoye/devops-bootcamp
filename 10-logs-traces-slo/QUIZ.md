# Module 10 — Quiz logs, traces, SLO, incidents

<details><summary>1. Pourquoi une application conteneurisée doit-elle écrire ses logs sur stdout ?</summary>

La plateforme (runtime + kubelet) capture stdout/stderr, gère la rotation, et un agent standard (Alloy, Fluent Bit…) collecte tout de la même façon, sans configuration par application. Écrire dans des fichiers dans le conteneur oblige à gérer volumes, rotation et collecte spécifiques, et les logs disparaissent avec le conteneur.
</details>

<details><summary>2. Quelle est la différence d'architecture entre Loki et Elasticsearch ?</summary>

Elasticsearch indexe le contenu complet des logs (recherche plein texte rapide, mais stockage et mémoire coûteux). Loki n'indexe que des labels (métadonnées à faible cardinalité) et stocke le contenu compressé en chunks sur du stockage objet ; les filtres sur le contenu sont appliqués à la lecture. Loki est beaucoup moins cher à opérer, au prix de requêtes plein texte plus lentes sur de gros volumes si les labels ne réduisent pas assez le périmètre.
</details>

<details><summary>3. Pourquoi ne pas mettre le <code>trace_id</code> ou l'ID utilisateur en label Loki ?</summary>

Chaque combinaison de labels crée un flux (stream) distinct avec son index et ses chunks. Des valeurs uniques par requête créent des millions de flux minuscules : index énorme, chunks inefficaces, ingestion et requêtes qui s'effondrent. Ces valeurs restent dans le contenu (filtrées avec `|=` ou `| json`) ou en structured metadata.
</details>

<details><summary>4. Trace, span, propagation de contexte ?</summary>

Une trace représente le parcours complet d'une requête à travers les services, identifiée par un trace_id. Elle se compose de spans (opérations avec nom, durée, attributs, statut, parent). La propagation de contexte transmet trace_id et span parent d'un service à l'autre (en-tête W3C `traceparent`) pour que tous les spans se rattachent à la même trace.
</details>

<details><summary>5. Qu'apporte OpenTelemetry ?</summary>

Un standard ouvert et neutre (API, SDK, instrumentations automatiques, protocole OTLP, Collector) pour produire et transporter métriques, logs et traces. On instrumente une fois et on peut changer de backend (Tempo, Jaeger, Datadog, Honeycomb…) en ne modifiant que la configuration du collecteur.
</details>

<details><summary>6. Head sampling vs tail sampling ?</summary>

Head : la décision de garder une trace est prise au début (ex. 10 % au hasard) — simple et peu coûteux, mais on perd la plupart des traces d'erreurs rares. Tail : la décision est prise à la fin, dans le collecteur, une fois la trace complète — on peut garder 100 % des traces en erreur ou lentes et un échantillon des autres, mais il faut mettre les spans en mémoire tampon (collecteur plus coûteux et à état).
</details>

<details><summary>7. Comment passer d'un log à la trace correspondante dans Grafana ?</summary>

L'application écrit le trace_id dans chaque log (contexte OTel du span courant). La datasource Loki a un « derived field » qui extrait le trace_id par regex (ou depuis la structured metadata) et en fait un lien vers la datasource Tempo. Inversement, Tempo est configuré avec « traces to logs » pour ouvrir les logs du même service et du même trace_id.
</details>

<details><summary>8. SLI, SLO, SLA, budget d'erreur ?</summary>

SLI : mesure de la qualité perçue (ratio bons événements / événements valides). SLO : objectif interne sur ce SLI et une fenêtre (99 % sur 30 j). SLA : engagement contractuel avec pénalités, moins strict que le SLO. Budget d'erreur : 1 − SLO, la quantité d'échec acceptable ; tant qu'il en reste on peut livrer et prendre des risques, épuisé on priorise la fiabilité.
</details>

<details><summary>9. Pourquoi un SLO de 100 % est-il une mauvaise idée ?</summary>

Coût exponentiel pour chaque « 9 » supplémentaire, aucune marge pour livrer ou expérimenter (chaque déploiement est un risque), et c'est imperceptible pour l'utilisateur dont le réseau, l'appareil et les dépendances sont eux-mêmes loin de 100 %. Le bon SLO est celui en dessous duquel les utilisateurs sont réellement mécontents.
</details>

<details><summary>10. Qu'est-ce que le burn rate et pourquoi alerter dessus plutôt que sur un seuil fixe ?</summary>

La vitesse de consommation du budget d'erreur relativement à la fenêtre du SLO (1 = consommé exactement en fin de période). Alerter sur un burn rate élevé relie l'alerte à l'impact réel sur l'objectif : une brève hausse d'erreurs ne réveille personne, une dégradation lente mais continue est détectée, et le niveau d'urgence (page vs ticket) découle de la vitesse de consommation.
</details>

<details><summary>11. Pourquoi deux fenêtres (longue et courte) dans une alerte de burn rate ?</summary>

La fenêtre longue (ex. 1 h) donne de la significativité et évite les faux positifs sur des pics courts. La fenêtre courte (ex. 5 min) confirme que le problème est toujours en cours : l'alerte se résout rapidement après la correction, au lieu de rester active tant que la fenêtre longue contient l'incident.
</details>

<details><summary>12. Quelles sont les étapes d'une bonne gestion d'incident ?</summary>

Détecter (alertes), déclarer et organiser (Incident Commander, canal dédié, rôles), communiquer (parties prenantes, page de statut), mitiger en priorité (rollback, feature flag, bascule) avant de chercher la cause profonde, tenir une chronologie, confirmer le retour à la normale, puis postmortem sans reproche avec actions correctives suivies.
</details>

<details><summary>13. Qu'est-ce qu'un postmortem « blameless » ?</summary>

Une analyse d'incident qui part du principe que les personnes ont agi raisonnablement avec les informations disponibles, et cherche les causes systémiques (processus, outils, garde-fous, tests, alertes) plutôt qu'un coupable. Sans cela, les gens dissimulent les erreurs et l'organisation n'apprend pas.
</details>

<details><summary>14. Une panne où les requêtes n'atteignent jamais l'application est-elle visible dans les métriques de l'application ?</summary>

Non : si la Gateway renvoie 503 parce qu'aucun pod n'est prêt, ou si le DNS/réseau est cassé en amont, l'application ne compte rien. Il faut aussi superviser les couches en amont (métriques de la Gateway/du load balancer) et faire des sondes externes (blackbox exporter, synthetic monitoring) qui mesurent l'expérience réelle.
</details>
