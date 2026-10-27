# Module 15 — Quiz Zabbix

<details><summary>1. Quels sont les composants de Zabbix et leur rôle ?</summary>

Le serveur (collecte, évaluation des triggers, événements, actions), la base de données (configuration, historique, tendances), le frontend web PHP (interface + API JSON-RPC), les agents (agent C ou agent 2 en Go, avec plugins) sur les hôtes, les proxys (collecte déportée dans une zone réseau ou un site distant), la Java gateway (JMX).
</details>

<details><summary>2. Agent passif ou actif ?</summary>

Passif : le serveur (ou proxy) se connecte à l'agent sur le port 10050 et demande chaque valeur. Actif : l'agent récupère la liste de ses checks et envoie les valeurs au serveur sur le port 10051. L'actif traverse mieux les pare-feu (flux sortant), passe mieux à l'échelle et est requis pour la surveillance des logs et l'auto-enregistrement.
</details>

<details><summary>3. Item, trigger, action : explique la chaîne.</summary>

Un item collecte une métrique (clé, type, intervalle, preprocessing). Un trigger est une expression sur des items qui, quand elle devient vraie, génère un événement et ouvre un problème avec une sévérité. Une action réagit aux événements selon des conditions (groupe, sévérité, hôte…) par des opérations : notifier via un media type, escalader, exécuter une commande distante ; avec des opérations de rétablissement.
</details>

<details><summary>4. À quoi servent les templates et les macros ?</summary>

Un template regroupe items, triggers, graphes, règles de découverte et dashboards réutilisables, liés à de nombreux hôtes : on maintient la supervision à un seul endroit. Les macros ({$CPU.UTIL.CRIT}) paramètrent les seuils et valeurs au niveau global, template ou hôte, sans dupliquer les templates.
</details>

<details><summary>5. Qu'est-ce que la LLD ?</summary>

La découverte de bas niveau (Low-Level Discovery) : une règle découvre dynamiquement des entités sur un hôte (systèmes de fichiers, interfaces, services, conteneurs, bases) et crée automatiquement pour chacune des items, triggers et graphes à partir de prototypes. Les entités disparues sont supprimées après un délai.
</details>

<details><summary>6. Comment ajouter automatiquement 500 nouveaux serveurs ?</summary>

Déployer l'agent (Ansible, image dorée) configuré en mode actif avec un `HostMetadata` significatif ; créer une action d'auto-enregistrement qui, selon les métadonnées, crée l'hôte, l'ajoute aux bons groupes et lie les bons templates. Alternative : network discovery, ou création par l'API depuis la CMDB/le provisioning (Terraform, Ansible `community.zabbix`).
</details>

<details><summary>7. Comment éviter une avalanche d'alertes quand un équipement réseau tombe ?</summary>

Dépendances de triggers (les triggers des serveurs derrière le switch dépendent du trigger du switch : ils ne génèrent pas de notification), corrélation d'événements, regroupement dans les actions, escalades raisonnables, et hystérésis (expression de rétablissement) pour éviter le clignotement.
</details>

<details><summary>8. Pourquoi créer une maintenance pendant une mise en production ?</summary>

Les redémarrages et indisponibilités prévus génèreraient des alertes inutiles (et des tickets, des réveils d'astreinte). Une maintenance suspend les notifications (avec ou sans collecte) sur les hôtes concernés pendant la fenêtre. Idéalement, la chaîne de déploiement la crée et la ferme automatiquement via l'API.
</details>

<details><summary>9. Comment superviser une application qui expose des métriques Prometheus avec Zabbix ?</summary>

Un item HTTP agent récupère `/metrics` (item maître), puis des items dépendants extraient les séries voulues avec le preprocessing « Prometheus pattern » (avec fonction d'agrégation sum/avg…), éventuellement « Change per second » pour transformer un counter en débit. Il existe aussi une règle LLD « Prometheus to JSON » pour découvrir des séries.
</details>

<details><summary>10. Zabbix ou Prometheus ?</summary>

Zabbix : tout-en-un, agent, SNMP, configuration en base via UI/API, idéal pour serveurs, réseau, infrastructure et legacy, avec alerting et escalades intégrés. Prometheus : modèle pull de séries temporelles à labels, service discovery, configuration en fichiers/CRD versionnés, PromQL, conçu pour les environnements dynamiques et Kubernetes. Beaucoup d'entreprises utilisent les deux, avec Grafana comme vitrine commune.
</details>

<details><summary>11. Historique et tendances : quelle différence ?</summary>

L'historique stocke chaque valeur collectée (rétention courte, ex. 7 à 30 jours). Les tendances stockent un agrégat horaire (min, max, moyenne, nombre) pour les valeurs numériques (rétention longue, ex. 1 à 5 ans) : utiles pour la capacité et les rapports, avec beaucoup moins de volume.
</details>

<details><summary>12. Un item est « not supported ». Ta démarche ?</summary>

Lire le message d'erreur dans la configuration de l'item (colonne Info) ; tester la clé directement sur l'agent (`zabbix_agent2 -t <clé>`) ou depuis le serveur (`zabbix_get -s <hôte> -k <clé>`) ; vérifier le type de valeur, le preprocessing, les droits de l'utilisateur zabbix (UserParameter), la connectivité et les paramètres `Server`/`ServerActive`/`Hostname`.
</details>
