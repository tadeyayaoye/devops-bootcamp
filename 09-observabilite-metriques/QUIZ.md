# Module 09 — Quiz métriques, alerting, Grafana

<details><summary>1. Monitoring vs observabilité ?</summary>

Le monitoring surveille des indicateurs prédéfinis et alerte sur des pannes connues. L'observabilité est la capacité à comprendre l'état interne d'un système à partir de ses signaux (métriques, logs, traces, profils), y compris pour diagnostiquer des problèmes imprévus, grâce à des données riches et corrélées.
</details>

<details><summary>2. Pourquoi Prometheus fonctionne-t-il en « pull » ?</summary>

Prometheus sait quelles cibles il doit trouver (service discovery) et détecte directement qu'une cible ne répond pas (`up == 0`). Les cibles n'ont pas à connaître le serveur de supervision, la charge est contrôlée par Prometheus, et on peut interroger `/metrics` à la main pour déboguer. Pour les jobs courts, on utilise le Pushgateway (ou OTLP/remote write dans d'autres architectures).
</details>

<details><summary>3. Counter, gauge, histogram, summary ?</summary>

Counter : valeur cumulative qui ne fait que croître (requêtes, erreurs) → `rate`/`increase`. Gauge : valeur instantanée qui monte et descend (mémoire, connexions). Histogram : distribution d'observations en buckets cumulés + somme + compte → percentiles agrégeables via `histogram_quantile`. Summary : quantiles calculés côté client, non agrégeables entre instances.
</details>

<details><summary>4. Qu'est-ce que la cardinalité et pourquoi est-ce dangereux ?</summary>

Le nombre de séries temporelles distinctes = combinaisons uniques de labels. Mettre des valeurs non bornées dans les labels (ID utilisateur, URL avec identifiants, adresse IP de client) crée des millions de séries : explosion mémoire et disque, requêtes lentes, Prometheus OOM. Les labels doivent avoir peu de valeurs possibles ; les détails individuels vont dans les logs ou les traces.
</details>

<details><summary>5. <code>rate</code>, <code>irate</code>, <code>increase</code> ?</summary>

`rate(x[5m])` : vitesse moyenne par seconde sur la fenêtre, robuste aux remises à zéro — pour les alertes et la plupart des graphes. `irate` : vitesse calculée sur les deux derniers points — très réactif mais bruité, pour des graphes de détail. `increase(x[1h])` : nombre d'incréments sur la fenêtre (≈ rate × durée).
</details>

<details><summary>6. Comment calcule-t-on un p95 de latence correctement sur plusieurs pods ?</summary>

`histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` : on calcule le taux de chaque bucket, on somme les buckets de toutes les instances en conservant le label `le`, puis on estime le quantile. On ne fait jamais la moyenne des p95 de chaque pod.
</details>

<details><summary>7. Pourquoi les percentiles plutôt que la moyenne ?</summary>

La moyenne masque la queue de distribution : 95 % de requêtes à 50 ms et 5 % à 5 s donnent une moyenne acceptable alors que 1 utilisateur sur 20 vit une expérience catastrophique (et ce sont souvent les plus gros clients, avec le plus de données). Les p95/p99 reflètent ce que vivent les utilisateurs les plus impactés.
</details>

<details><summary>8. Méthodes RED et USE ?</summary>

RED (services) : Rate, Errors, Duration — ce que voit l'appelant d'un service. USE (ressources) : Utilization, Saturation, Errors — pour CPU, mémoire, disques, réseau, pools. Les 4 golden signals de Google (latence, trafic, erreurs, saturation) combinent les deux.
</details>

<details><summary>9. Qu'est-ce qu'un ServiceMonitor ? Pourquoi une cible peut-elle ne pas apparaître ?</summary>

Une CRD du Prometheus Operator qui décrit quels Services (par labels) scraper, sur quel port nommé et quel chemin ; l'opérateur génère la configuration de Prometheus. Absente si : le ServiceMonitor ne correspond pas au `serviceMonitorSelector` du Prometheus (labels de release), le namespace n'est pas couvert, le sélecteur ne trouve pas le Service, le port n'est pas nommé ou mal nommé. DOWN si : NetworkPolicy, mauvais chemin, appli qui ne répond pas.
</details>

<details><summary>10. À quoi sert le <code>for</code> dans une règle d'alerte ?</summary>

La condition doit rester vraie pendant cette durée avant que l'alerte passe de pending à firing : on filtre les pics transitoires et on réduit les faux positifs. Trop long, on détecte trop tard ; trop court, l'alerte est bruyante.
</details>

<details><summary>11. Que fait Alertmanager que Prometheus ne fait pas ?</summary>

Déduplication (plusieurs Prometheus HA), groupement des alertes liées en une notification, routage selon les labels vers les bonnes équipes/canaux, inhibition (une alerte en masque d'autres), silences (maintenances), répétitions, intégrations (Slack, PagerDuty, Opsgenie, mail, webhooks).
</details>

<details><summary>12. Qu'est-ce qu'une bonne alerte ?</summary>

Elle porte sur un symptôme ressenti par les utilisateurs (ou une menace imminente : disque plein dans 4 h), elle est actionnable et urgente, rarement fausse, avec une sévérité adaptée (page vs ticket) et un runbook. Le reste va dans des dashboards ou des tickets. Trop d'alertes = fatigue d'alerte = vraies alertes ignorées.
</details>

<details><summary>13. Qu'est-ce que l'alerte Watchdog ?</summary>

Une alerte toujours active (`vector(1)`) qui prouve que toute la chaîne Prometheus → Alertmanager → récepteur fonctionne. On la route vers un service de « dead man's switch » (ex. Healthchecks.io, DeadMansSnitch) qui alerte s'il cesse de la recevoir : on détecte ainsi une supervision elle-même en panne.
</details>

<details><summary>14. Pourquoi des dashboards « as code » ?</summary>

Versionnés et revus comme du code, reproductibles sur tous les environnements et clusters, restaurables après un incident, cohérents (pas de copies divergentes modifiées à la main), générables à partir de templates (Grafonnet, SDK). Les changements manuels dans l'UI ne survivent pas : il faut modifier la source.
</details>

<details><summary>15. Prometheus pour la rétention longue et la haute disponibilité ?</summary>

Prometheus seul stocke localement, sur un seul nœud, avec une rétention limitée. Pour la HA on lance deux Prometheus identiques (dédupliqués par Alertmanager). Pour la vue globale multi-clusters et la rétention longue : remote_write ou sidecar vers Thanos, Grafana Mimir, Cortex ou VictoriaMetrics (stockage objet, requêtes globales, downsampling).
</details>
