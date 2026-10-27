# Module 15 — Labs Zabbix

> ⏱ ~3 h · Prérequis : le labo Ansible du module 05 (web1, web2, db1 avec taskapi et nginx).
> RAM : ~1,5 Go pour Zabbix. Le cluster kind n'est pas nécessaire.

---

## Lab 15.1 — Démarrer Zabbix (≈ 20 min)

```bash
cd ~/devops-bootcamp
docker compose -f 05-ansible/lab/compose.yaml up -d            # les 3 « serveurs » (réseau ansible-lab_lab)
(cd infra/ansible && ansible-playbook playbooks/site.yml)        # taskapi et nginx à jour sur web1/web2
cat 15-zabbix/lab/compose.yaml                                    # lis-le : base, serveur, web, agent, récepteur
docker compose -f 15-zabbix/lab/compose.yaml up -d
docker compose -f 15-zabbix/lab/compose.yaml ps
docker compose -f 15-zabbix/lab/compose.yaml logs zabbix-server | tail -20   # création du schéma au 1er démarrage
```

Ouvre http://localhost:8091 → **Admin / zabbix**. Change immédiatement le mot de passe (*User settings → Profile*).

Puis crée un **API token** (*User settings → API tokens → Create*) et garde-le pour la suite (jamais dans Git) :

```bash
read -rs ZBX_TOKEN && export ZBX_TOKEN
15-zabbix/scripts/zbx.sh apiinfo.version '{}'
15-zabbix/scripts/zbx.sh host.get '{"output":["host","status"]}'
```

**Premier problème, premier debug** : *Monitoring → Hosts* → l'hôte « Zabbix server » a une icône **ZBX rouge**. Pourquoi ? (Son interface agent pointe sur `127.0.0.1`, or l'agent tourne dans un autre conteneur.) Corrige : *Data collection → Hosts → Zabbix server → Interfaces* → Connect to **DNS** `zabbix-agent`. Quelques minutes plus tard, l'icône passe au vert.

---

## Lab 15.2 — Déployer l'agent sur les serveurs avec Ansible (≈ 30 min)

Écris le rôle `infra/ansible/roles/zabbix_agent/` :
- installe le paquet `zabbix-release` (dépôt officiel **7.0 LTS** pour Ubuntu 24.04 : Ubuntu ne fournit plus l'agent) puis `zabbix-agent2` et `supervisor` ;
- template `/etc/zabbix/zabbix_agent2.conf` : `Server` et `ServerActive` = `172.30.0.20`, `Hostname={{ inventory_hostname }}`, `HostMetadata` contenant `bootcamp` et les groupes de l'hôte, `LogType=console` ;
- sur les serveurs `web` uniquement, deux **UserParameter** : `taskapi.readyz` (code HTTP de `/readyz`) et `taskapi.process.count` (nombre de processus uvicorn) ;
- un programme **supervisor** qui lance `zabbix_agent2` (pas de systemd dans le labo) et un handler de redémarrage.

Et le playbook `infra/ansible/playbooks/zabbix-agent.yml` (hôtes `lab`), avec une vérification `zabbix_agent2 -t agent.ping`.

```bash
cd infra/ansible
ansible-playbook playbooks/zabbix-agent.yml
ansible-playbook playbooks/zabbix-agent.yml                     # idempotent : changed=0
ansible web1 -b -m command -a 'zabbix_agent2 -t taskapi.readyz -c /etc/zabbix/zabbix_agent2.conf'
cd -
```

À ce stade, aucun hôte n'apparaît dans Zabbix : il manque l'auto-enregistrement.

---

## Lab 15.3 — Auto-enregistrement : les serveurs s'ajoutent tout seuls (≈ 20 min)

Dans l'UI :
1. *Data collection → Host groups → Create* : `Bootcamp/Linux`.
2. *Alerts → Actions → **Autoregistration actions** → Create action* : nom `Auto-enregistrement bootcamp`, condition **Host metadata contains `bootcamp`**, opérations **Add host**, **Add to host groups** `Bootcamp/Linux`, **Link templates** `Linux by Zabbix agent active`.

En une à deux minutes, `web1`, `web2` et `db1` apparaissent dans *Monitoring → Hosts*, avec des dizaines de métriques (*Latest data*). Ouvre le dashboard d'un hôte : CPU, mémoire, systèmes de fichiers (découverts par **LLD**), interfaces réseau.

Fais la même chose **par l'API** (supprime l'action et les hôtes, puis lance ton script) : écris `15-zabbix/solutions/scripts/zbx-autoregistration.sh` ou lis la solution, avec `hostgroup.create`, `template.get`, `action.create` (`eventsource: 2`).

```bash
15-zabbix/scripts/zbx.sh host.get '{"output":["host"],"selectParentTemplates":["name"]}'
```

---

## Lab 15.4 — Superviser l'application (≈ 45 min)

Crée un **template** `Template taskapi` (*Data collection → Templates → Create*), lié aux hôtes `web1` et `web2`, avec :

1. **Items agent** sur tes UserParameter : `taskapi.readyz` (numérique) et `taskapi.process.count`.
2. **Item HTTP agent** maître : URL `http://{HOST.CONN}/metrics`, type de valeur *Text*, intervalle 30 s, historique 1 h.
3. **Items dépendants** de l'item maître, avec un preprocessing **Prometheus pattern** :
   - `taskapi.http.requests.total` ← `http_requests_total` avec la fonction **sum** ;
   - `taskapi.http.errors.total` ← `http_requests_total{status=~"5.."}` avec la fonction **sum**, puis un 2ᵉ preprocessing **Change per second** ;
   - `taskapi.tasks.created` ← `taskapi_tasks_created_total`.
4. **Web scenario** `taskapi` : étape GET `http://{HOST.CONN}/readyz`, code attendu 200, chaîne requise `ready` ; étape GET `/api/tasks`, code 200.
5. **Triggers** :
   - `last(/Template taskapi/taskapi.readyz)<>200` → *High* « taskapi n'est pas prêt sur {HOST.NAME} » ;
   - `last(/Template taskapi/taskapi.process.count)=0` → *Disaster* « processus taskapi absent » (dépendance : le trigger *High* dépend de celui-ci) ;
   - échec du web scenario → *High* ;
   - `avg(/Template taskapi/taskapi.http.errors.total,5m)>{$TASKAPI.ERRORS.MAX}` avec la macro `{$TASKAPI.ERRORS.MAX}` = 1 au niveau du template.

Vérifie dans *Latest data* que les valeurs arrivent (sinon : *Data collection → Hosts → Items* → colonne *Info*, icône rouge = élément non supporté, avec le message).

Génère du trafic : `python3 scripts/load.py http://localhost:8081 --duration 300 --concurrency 3 &`

---

## Lab 15.5 — Alerter (≈ 25 min)

1. *Alerts → Media types → Create* : type **Webhook**, nom `Bootcamp sink`, paramètres `url` = `http://alert-sink:8080/`, `subject` = `{ALERT.SUBJECT}`, `message` = `{ALERT.MESSAGE}`, `severity` = `{EVENT.SEVERITY}`, script : le contenu de [lab/webhook.js](lab/webhook.js). Bouton *Test*.
2. *Users → Users → Admin → Media* : ajoute ce media (destinataire quelconque, sévérités *Average* et plus).
3. *Alerts → Actions → Trigger actions → Create* : condition *Host group = Bootcamp/Linux* et *Trigger severity ≥ High*, opération *Send message* à Admin, + *Recovery operations*.

Provoque des pannes et regarde arriver les notifications :

```bash
docker compose -f 15-zabbix/lab/compose.yaml logs -f alert-sink        # dans un autre terminal
(cd infra/ansible && ansible web1 -b -m command -a 'supervisorctl stop taskapi')
# … attends l'alerte (Monitoring → Problems), puis :
(cd infra/ansible && ansible web1 -b -m command -a 'supervisorctl start taskapi')
```

Observe : le problème, l'événement de résolution, la notification de rétablissement, et la **dépendance** (seul le trigger racine notifie ?).

---

## Lab 15.6 — Maintenance pendant une mise en production (≈ 20 min)

Une MEP est prévue sur web2 : pendant 30 minutes, on ne veut **pas** d'alerte.

```bash
NOW=$(date +%s)
WEB2=$(15-zabbix/scripts/zbx.sh host.get '{"filter":{"host":["web2"]}}' | jq -r '.[0].hostid')
15-zabbix/scripts/zbx.sh maintenance.create "{
  \"name\": \"MEP taskapi web2 $(date +%F_%H%M)\",
  \"active_since\": $NOW, \"active_till\": $((NOW + 1800)),
  \"hosts\": [{\"hostid\": \"$WEB2\"}],
  \"timeperiods\": [{\"timeperiod_type\": 0, \"period\": 1800}],
  \"description\": \"RFC-1234 — rolling update taskapi\"
}"
```

Lance le déploiement progressif du module 05 (`ansible-playbook playbooks/rolling-update.yml -e new_version=2.0.0`) : web2 redémarre, Zabbix voit le problème (icône clé à molette 🔧) mais **ne notifie pas**. C'est ce qu'une chaîne de MEP (XL Release, module 16) doit faire automatiquement avant chaque déploiement.

---

## 🏁 Challenge (sans guide)

1. **Batch → Zabbix** : à la fin de la chaîne Airflow du module 14, envoie le statut de l'arrêté à Zabbix avec `zabbix_sender` (item de type *Zabbix trapper* `batch.arrete.status` sur un hôte `batch`), et crée un trigger « arrêté non terminé à 5 h » avec `nodata()`.
2. **PostgreSQL** : sur db1, crée un utilisateur de supervision et lie le template `PostgreSQL by Zabbix agent 2` (macros `{$PG.URI}`, `{$PG.USER}`, `{$PG.PASSWORD}`).
3. **As code** : exporte ton `Template taskapi` en YAML (*Export*) dans `15-zabbix/templates/`, supprime-le, puis réimporte-le par l'API (`configuration.import`). C'est ainsi qu'on versionne la supervision.
4. **Grafana** : dans le Grafana du module 09, installe le plugin Zabbix (`alexanderzobnin-zabbix-app`) et affiche les métriques de web1 à côté de celles de Prometheus.

---

## ✅ Validation

```bash
make check-15
```
