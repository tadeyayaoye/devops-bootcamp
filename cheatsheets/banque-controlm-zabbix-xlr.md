# Parcours banque — fiche mémo (Control-M, Airflow, Zabbix, XL Release)

## Vocabulaire production

RFC · CAB · changement standard / normal / urgent · MEP · gel (freeze) · fenêtre de MEP · DEX (dossier d'exploitation) · consignes de pilotage · plan de production · ODATE · New Day · astreinte · N1/N2/N3 · PCA/PRA · RTO/RPO · DORA (règlement UE 2022/2554) ≠ métriques DORA.

## Control-M

| Action | UI | CLI `ctm` (Automation API) |
|---|---|---|
| Valider des définitions | — | `ctm build fichier.json` |
| Tester | — | `ctm run fichier.json [-i]` |
| Déployer | Planning → Deploy | `ctm deploy fichier.json` |
| Exporter l'existant | — | `ctm deploy jobs::get -s "folder=XXX*"` |
| Ordonnancer | Order | `ctm run order <server> <folder>` |
| Statut / sysout | Monitoring → Output | `ctm run status <runId>` · `ctm run job:output::get <jobId>` |
| Relancer / forcer OK / bloquer / tuer | Rerun / Set to OK / Hold / Kill | `ctm run job::rerun <jobId>` (aussi `setToOk`, `hold`, `kill`) (vérifie avec `ctm run -h`) |

JSON : `Folder` · `Job:Command` · `Job:Script` · `Job:FileWatcher:Create` · `When` (`WeekDays`, `FromTime`, calendriers) · `Flow` (`Sequence`) · `WaitForEvents` / `AddEvents` / `DeleteEvents` · `Resource:Semaphore` / `Resource:Mutex` · `Rerun` · `If` + `Mail` · variables `%%ODATE` (AAMMJJ), `%%$ODATE` (AAAAMMJJ), `%%JOBNAME`.

## Airflow 3 (docker compose)

```bash
docker compose exec airflow-scheduler airflow dags list
docker compose exec airflow-scheduler airflow dags list-import-errors
docker compose exec airflow-scheduler airflow dags unpause <dag>
docker compose exec airflow-scheduler airflow dags trigger <dag> --logical-date 2026-10-27T22:00:00+01:00
docker compose exec airflow-scheduler airflow pools set <pool> <slots> "<desc>"
docker compose exec airflow-scheduler airflow backfill create --dag-id <dag> --from-date … --to-date …
docker compose exec airflow-scheduler airflow tasks test <dag> <task> <date>
```

DAG ↔ Folder · logical date / `{{ ds_nodash }}` ↔ ODATE · FileSensor ↔ File Watcher · pool ↔ ressource · Asset ↔ condition · Clear ↔ Rerun · Mark success ↔ Set to OK · Pause ↔ Hold.

## Zabbix 7.0 LTS

| | |
|---|---|
| Ports | agent passif **10050**, serveur/actif **10051** |
| Tester une clé sur l'agent | `zabbix_agent2 -t <clé> -c /etc/zabbix/zabbix_agent2.conf` |
| Tester depuis le serveur | `zabbix_get -s <hôte> -k <clé>` |
| Envoyer une valeur (trapper) | `zabbix_sender -z <serveur> -s <hôte> -k <clé> -o <valeur>` |
| Agent : paramètres clés | `Server=` · `ServerActive=` · `Hostname=` (= nom dans Zabbix) · `HostMetadata=` · `UserParameter=clé,commande` |

Triggers : `last(/h/k)=0` · `avg(/h/k,5m)>{$SEUIL}` · `min(/h/k,10m)<10` · `nodata(/h/k,5m)=1` · `count(/h/k,5m)>10`. Sévérités : Information < Warning < Average < High < Disaster.

API JSON-RPC : `POST /api_jsonrpc.php` · `user.login {"username","password"}` · ensuite en-tête `Authorization: Bearer <token>` · `host.get` · `problem.get` · `maintenance.create` · `action.create` (eventsource 2 = auto-enregistrement) · `configuration.import`.

## XL Release (Digital.ai Release)

Folder › Template › Release › Phase › Task (Manual, Gate, User input, Notification, Jenkins: Build, Webhook, Script, Create release) · variables `${x}` (dont *password*) · Teams (séparation des tâches) · Blackout periods (gel) · Retry / Skip (commentaire !) / Abort.

```bash
xl apply -f template.yaml                    # Release as code
curl -u admin:… http://localhost:5516/api/v1/templates
curl -u admin:… -X POST -H 'Content-Type: application/json' \
  http://localhost:5516/api/v1/templates/<id>/start -d '{"releaseTitle":"…","variables":{"version":"…"}}'
```
