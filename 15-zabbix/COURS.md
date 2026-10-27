# Module 15 — Supervision d'infrastructure avec Zabbix

> **Objectif** : comprendre l'architecture et le modèle de données de Zabbix (hôtes, items, triggers, templates), superviser des serveurs avec l'agent, des applications par HTTP, alerter proprement, automatiser (auto-enregistrement, découverte, API, Ansible), et savoir **positionner Zabbix face à Prometheus**.
>
> **Durée** : cours ~1 h 45 · labs ~3 h · quiz 30 min · *Prérequis : le labo Ansible du module 05 (3 « serveurs » SSH).*

---

## 1. Zabbix en deux mots

Logiciel de supervision **open source** (licence AGPLv3 depuis la 7.0, gratuit, support commercial optionnel), créé en 2001, très répandu dans les **infrastructures « classiques »** : serveurs physiques et virtuels, réseau (SNMP), bases de données, middleware, applications. C'est l'un des outils les plus présents dans les banques et grands comptes français, souvent aux côtés de Centreon/Nagios (historiques) et de Dynatrace (APM).

Versions : une **LTS** tous les ~18 mois, supportée 5 ans (**7.0 LTS** sortie en juin 2024, **8.0 LTS** annoncée pour 2026) et des versions intermédiaires (7.2, 7.4) au support court. **En production bancaire : toujours une LTS.** Ce module utilise la 7.0 LTS.

---

## 2. Architecture

```
                                 ┌──────────────────────┐
  navigateur ───────────────────►│ Frontend web (PHP)   │──┐
  API JSON-RPC (scripts, Ansible)►│ /api_jsonrpc.php     │  │
                                 └──────────────────────┘  │
                                                           ▼
 ┌────────────┐  passif : le serveur interroge   ┌─────────────────────┐     ┌──────────────┐
 │ Agent 2    │◄──── :10050 ─────────────────────│   Zabbix Server     │────►│ Base (Postgre│
 │ (hôte Linux│                                   │ collecte, triggers, │     │ SQL / MySQL) │
 │  /Windows) │───── :10051 ─────────────────────►│ événements, actions │     │ config +     │
 └────────────┘  actif : l'agent envoie            └─────────┬───────────┘     │ historique + │
                                                             │                 │ tendances    │
 ┌────────────┐                                    ┌─────────┴───────────┐     └──────────────┘
 │ SNMP, IPMI,│◄────── interrogation ─────────────│   Zabbix Proxy       │ (site distant, DMZ,
 │ HTTP, JMX, │                                    │ collecte locale,     │  zone réseau cloisonnée)
 │ ODBC…      │                                    │ bufferise, renvoie   │
 └────────────┘                                    └──────────────────────┘
```

| Composant | Rôle |
|---|---|
| **Server** | cœur : planifie les collectes, stocke les valeurs, évalue les **triggers**, génère les **événements** et **problèmes**, exécute les **actions** |
| **Base de données** | configuration + **historique** (valeurs brutes, courte rétention) + **tendances** (min/max/moyenne horaire, longue rétention). Souvent PostgreSQL + TimescaleDB pour les gros volumes |
| **Frontend** | interface web PHP + **API JSON-RPC** |
| **Agent / Agent 2** | sur l'hôte supervisé : métriques système, logs, processus, commandes personnalisées. Agent 2 (Go) ajoute des **plugins** (Docker, PostgreSQL, MySQL, Redis, MongoDB…) |
| **Proxy** | collecte pour le compte du serveur dans une zone réseau séparée (site distant, DMZ, réseau cloisonné) : très utilisé en banque où les flux sont filtrés |
| **Java gateway** | supervision JMX (applications Java) |

### Passif vs actif

| Mode | Qui initie ? | Avantage |
|---|---|---|
| **Passif** | le serveur se connecte à l'agent (port **10050**) | simple, le serveur maîtrise le rythme |
| **Actif** | l'agent récupère sa liste de checks et **envoie** ses valeurs au serveur (port **10051**) | traverse mieux les pare-feu (flux sortant de l'hôte), passe à l'échelle, indispensable pour les logs et l'auto-enregistrement |

---

## 3. Le modèle de données

```
Template ──lié à──► Host ──possède──► Items ──évalués par──► Triggers ──génèrent──► Events / Problems ──► Actions
   │                  │                 │                                                                    │
   │              Interfaces       Preprocessing                                                    notifications,
   │              (agent, SNMP…)   (JSONPath, regex,                                                commandes distantes
   │              Macros {$...}     Prometheus…)                                                    (remédiation)
   └── LLD (découverte de bas niveau : 1 règle → N items/triggers par disque, interface, service…)
```

| Objet | Description | Exemple |
|---|---|---|
| **Host** | une entité supervisée (serveur, équipement, application) | `web1` |
| **Host group** | regroupement (droits, actions, maintenance) | `Bootcamp/Linux` |
| **Item** | une métrique collectée, avec une **clé**, un type, un intervalle | `system.cpu.util`, `vfs.fs.size[/,pused]`, `proc.num[uvicorn]` |
| **Type d'item** | agent, agent actif, HTTP agent, SNMP, simple check, calculé, dépendant, trapper, script… | |
| **Preprocessing** | transformation avant stockage | JSONPath, regex, multiplicateur, « change per second », **Prometheus pattern** |
| **Trigger** | une **expression** sur des items qui définit un problème, avec une **sévérité** | `avg(/web1/system.cpu.util,5m)>90` |
| **Sévérités** | Not classified, Information, Warning, Average, High, Disaster | |
| **Event / Problem** | changement d'état d'un trigger ; un problème reste ouvert jusqu'à sa résolution | |
| **Action** | règle « si événement correspondant aux conditions → opérations » (notifier, escalader, exécuter une commande) | |
| **Media type** | canal de notification : e-mail, SMS, **webhook** (Slack, Teams, ServiceNow, PagerDuty…) | |
| **Template** | ensemble réutilisable d'items, triggers, graphes, LLD, macros. Des centaines fournis (« Linux by Zabbix agent », « PostgreSQL by Zabbix agent 2 », « Docker by Zabbix agent 2 »…) | |
| **Macro** | variable `{$CPU.UTIL.CRIT}` définie au niveau global / template / hôte → seuils ajustables sans toucher au template | |
| **Maintenance** | période où les problèmes ne déclenchent pas d'alerte (MEP, intervention planifiée) | |
| **Web scenario** | suite de requêtes HTTP (supervision synthétique) avec contrôles de code, de contenu, de temps de réponse | |

### Expressions de trigger (syntaxe 6.0+)

```
last(/web1/net.tcp.service[http])=0                         # le service HTTP ne répond plus
avg(/web1/system.cpu.util,5m)>{$CPU.UTIL.CRIT}              # CPU moyen sur 5 min au-dessus du seuil
min(/web1/vfs.fs.size[/,pfree],10m)<10                      # moins de 10 % libres pendant 10 min
nodata(/web1/agent.ping,5m)=1                               # plus aucune donnée : agent mort ?
count(/web1/log[/var/log/app.log,ERROR],5m)>10              # plus de 10 erreurs dans les logs en 5 min
last(/web1/web.test.fail[taskapi])<>0                       # scénario web en échec
```

**Expression de rétablissement** (*recovery expression*) et **hystérésis** : déclencher à 90 %, ne résoudre qu'en dessous de 80 % → pas de « clignotement ». **Dépendances de triggers** : si le switch est en panne, ne pas alerter sur les 40 serveurs derrière.

---

## 4. Collecter au-delà de l'agent

- **HTTP agent** : interroger une URL (API, endpoint `/metrics` Prometheus, page de statut) et extraire les valeurs par preprocessing. Avec un **item maître** et des **items dépendants**, une seule requête alimente N métriques.
- **UserParameter** : commande personnalisée exécutée par l'agent (`UserParameter=taskapi.ready,curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/readyz`).
- **SNMP** : réseau, stockage, équipements (traps et polling).
- **ODBC** : requêtes SQL directes (métier : « nombre de virements en attente »).
- **Log monitoring** (agent actif) : `log[]`, `logrt[]` avec filtres regex.
- **Zabbix sender / trapper** : un script pousse une valeur (fin d'un batch, résultat d'un contrôle). Très utile avec un ordonnanceur : le job batch envoie son statut à Zabbix.

---

## 5. Automatiser Zabbix (la partie « DevOps »)

| Besoin | Mécanisme |
|---|---|
| Ajouter automatiquement les nouveaux serveurs | **Auto-enregistrement** (*autoregistration*) : l'agent actif s'annonce avec un `HostMetadata` ; une action crée l'hôte, l'ajoute à un groupe, lie les templates |
| Découvrir des éléments dynamiques sur un hôte | **LLD** (*low-level discovery*) : systèmes de fichiers, interfaces, services, conteneurs, bases… |
| Découvrir des hôtes sur un réseau | **Network discovery** |
| Piloter la configuration par code | **API JSON-RPC** (`host.create`, `template.get`, `maintenance.create`…), collection Ansible **`community.zabbix`**, provider Terraform communautaire, import/export YAML des templates |
| Déployer l'agent | Ansible (rôle `zabbix_agent` du lab), image dorée, paquets |
| Maintenance pendant une MEP | `maintenance.create` appelé par la chaîne de déploiement (XL Release, Jenkins…) |
| Ticket automatique | media type webhook vers ServiceNow / Jira |

### L'API

```bash
# Authentification : obtenir un jeton (ou mieux : un API token créé dans l'UI, Users → API tokens)
curl -s -X POST http://localhost:8091/api_jsonrpc.php -H 'Content-Type: application/json-rpc' \
  -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"…"},"id":1}'
# Appels suivants : en-tête  Authorization: Bearer <jeton>
curl -s -X POST http://localhost:8091/api_jsonrpc.php -H 'Content-Type: application/json-rpc' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","method":"problem.get","params":{"recent":true,"sortfield":"eventid","sortorder":"DESC"},"id":2}'
```

---

## 6. Zabbix ou Prometheus ?

| | Zabbix | Prometheus (+ Grafana, Alertmanager) |
|---|---|---|
| Cible historique | serveurs, réseau, infra « stable » | services dynamiques, conteneurs, Kubernetes |
| Collecte | agent (passif/actif), SNMP, HTTP, JMX, ODBC… | **pull** HTTP de `/metrics` (exporters) |
| Configuration | **UI + base de données** (+ API, templates) | **fichiers / CRD** versionnés (ServiceMonitor, PrometheusRule) |
| Modèle | hôte → items (clés) | séries temporelles à labels |
| Découverte | auto-enregistrement, LLD, network discovery | service discovery (Kubernetes, cloud, Consul) |
| Alerting | triggers + actions + escalades intégrés | règles + Alertmanager |
| Requêtes | fonctions de trigger, graphes | **PromQL** très expressif |
| Tout-en-un | ✅ (collecte, stockage, UI, alertes, cartes, rapports) | ❌ assemblage de briques |
| Éphémère (pods qui vivent 5 min) | ⚠ peu adapté | ✅ conçu pour |

En pratique dans une banque : **Zabbix pour l'infrastructure et le legacy**, **Prometheus/Grafana pour les plateformes conteneurs** (OpenShift embarque Prometheus), et **Grafana** souvent comme vitrine commune (plugin Zabbix pour Grafana). Zabbix sait aussi lire des endpoints Prometheus (preprocessing « Prometheus pattern ») — c'est ce que tu feras sur `/metrics` de taskapi.

---

## 7. Bonnes pratiques

- **Templates** plutôt que des items par hôte ; seuils en **macros** ; jamais de modification directe des templates fournis (les cloner).
- **Sévérités** cohérentes avec l'astreinte : *High/Disaster* = on réveille quelqu'un ; *Warning* = ticket.
- **Maintenances** systématiques pendant les MEP (déclenchées par la chaîne de déploiement).
- **Dépendances de triggers** pour éviter les avalanches d'alertes.
- **Rétention** : historique court (7-30 j), tendances longues (1-5 ans) ; partitionnement / TimescaleDB au-delà de quelques milliers de valeurs par seconde.
- **Proxys** par zone réseau ; haute disponibilité du serveur (cluster natif depuis la 6.0).
- **Supervision de la supervision** : alerte si le serveur Zabbix lui-même est saturé (file d'attente, *pollers busy*).
- Configuration gérée **as code** (API/Ansible + export YAML des templates dans Git).

---

## Pour aller plus loin

- [Documentation Zabbix 7.0 LTS](https://www.zabbix.com/documentation/7.0/en/manual)
- [Zabbix — intégrations et templates officiels](https://www.zabbix.com/integrations)
- [Collection Ansible community.zabbix](https://galaxy.ansible.com/ui/repo/published/community/zabbix/)
- [zabbix-docker (dépôt officiel)](https://github.com/zabbix/zabbix-docker)
