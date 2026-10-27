# Module 14 — Labs ordonnancement

> ⏱ ~3 h 30 · RAM : Airflow demande ~4 Go. Arrête le cluster et la CI avant (`make tf-destroy ci-down`, après `make sealed-key-backup` si besoin).
> Tu travailles dans `batch/` (racine du repo). Les **scripts batch** sont fournis dans `14-ordonnancement/batch/scripts/` : ton travail, c'est de les **ordonnancer**.

---

## Lab 14.1 — Comprendre la chaîne à la main (≈ 20 min)

Avant tout outil, joue la chaîne comme le ferait un pilote, pour comprendre chaque job :

```bash
cd ~/devops-bootcamp
S=14-ordonnancement/batch/scripts
export BATCH_DATA=/tmp/batch-manuel BATCH_DUREE_CHARGEMENT=0 BATCH_DUREE_CALCUL=0
bash $S/generer_transactions.sh 20261027 200          # le partenaire dépose son fichier
bash $S/controler_fichier.sh 20261027; echo "rc=$?"
bash $S/charger_transactions.sh 20261027
bash $S/charger_transactions.sh 20261027               # relance : le résultat est-il doublé ?
bash $S/calculer_soldes.sh 20261027
bash $S/generer_reporting.sh 20261027 && cat $BATCH_DATA/out/reporting_20261027.txt
bash $S/transferer_partenaire.sh 20261027 && ls $BATCH_DATA/out/partenaire
bash $S/archiver.sh 20261027
```

Lis chaque script (ils sont courts) et réponds :
1. Pourquoi `generer_transactions.sh` écrit-il dans un fichier temporaire puis le renomme ?
2. Quels jobs sont **idempotents** ? Comment le chargement l'est-il devenu ?
3. Pourquoi le contrôle utilise-t-il un **trailer** ? Teste : `bash $S/generer_transactions.sh 20261028 50 corrompu && bash $S/controler_fichier.sh 20261028; echo rc=$?`
4. À quoi servent le `.sha256` et le fichier `.ok` déposés pour le partenaire ?

Reporte les réponses dans tes consignes de pilotage (module 13, exercice 13.3).

---

## Lab 14.2 — Installer Airflow (≈ 25 min)

```bash
mkdir -p batch/airflow && cd batch/airflow
curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.3.2/docker-compose.yaml'
mkdir -p dags logs plugins config data
echo -e "AIRFLOW_UID=$(id -u)" > .env
# pas d'exemples : on veut un Airflow propre
sed -i "s/AIRFLOW__CORE__LOAD_EXAMPLES: 'true'/AIRFLOW__CORE__LOAD_EXAMPLES: 'false'/" docker-compose.yaml
cp ../../14-ordonnancement/labs/airflow/docker-compose.override.yaml .
cat docker-compose.override.yaml          # lis-le : port 8090, scripts et données montés dans le worker
docker compose config >/dev/null && echo "compose OK"
docker compose up airflow-init            # attends "exited with code 0"
docker compose up -d
docker compose ps                         # tout doit être healthy (1-2 min)
```

Ouvre http://localhost:8090 (airflow / airflow).

> Une version plus récente qu'Airflow 3.3.2 est sortie ? Prends son `docker-compose.yaml` : le reste du lab doit fonctionner, sinon c'est un bon exercice de lecture des *release notes*.

Explore l'architecture réelle :

```bash
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
# api-server, scheduler, dag-processor, worker, triggerer, postgres, redis : retrouve le rôle de chacun dans le cours
```

**Ressource quantitative** : crée le pool qui protège le grand livre.

```bash
docker compose exec airflow-scheduler airflow pools set db_batch 1 "Accès exclusif au grand livre comptable"
docker compose exec airflow-scheduler airflow pools list
```

---

## Lab 14.3 — Écrire la chaîne ARRETE_COMPTABLE (≈ 50 min)

Crée `batch/airflow/dags/arrete_comptable.py` :

- **planification** : `schedule="0 22 * * 1-5"`, fuseau `Europe/Paris`, `catchup=False`, `max_active_runs=1` ;
- **calendrier TARGET** : un `ShortCircuitOperator` qui renvoie `False` les jours de fermeture TARGET (1ᵉʳ janvier, Vendredi saint, lundi de Pâques, 1ᵉʳ mai, 25 et 26 décembre). Calcule Pâques par algorithme, sans librairie ;
- `attendre_fichier` : `FileSensor` sur `/opt/airflow/data/in/transactions_{{ ds_nodash }}.csv`, connexion `fs_batch`, `mode="reschedule"`, timeout 2 h ;
- un `BashOperator` par script, avec la date `{{ ds_nodash }}` en argument ;
- `controler_fichier` **sans relance**, `charger_transactions` avec **2 relances**, chargement et soldes dans le **pool `db_batch`** ;
- reporting et transfert **en parallèle**, puis archivage ;
- `fin_arrete` publie l'**Asset** `batch://arrete_comptable/termine` ;
- `on_failure_callback` qui affiche une alerte ;
- un `doc_md` qui documente la chaîne (affiché dans l'UI).

Le dossier `dags/` est surveillé : en quelques secondes le DAG apparaît dans l'UI (sinon : `docker compose logs airflow-dag-processor | tail -30` pour l'erreur d'import).

```bash
docker compose exec airflow-scheduler airflow dags list | grep arrete
docker compose exec airflow-scheduler airflow dags list-import-errors
```

Observe le **graphe** dans l'UI : est-il identique à la chaîne du cours ?

---

## Lab 14.4 — Faire tourner une nuit de production (≈ 40 min)

```bash
docker compose exec airflow-scheduler airflow dags unpause arrete_comptable
docker compose exec airflow-scheduler airflow dags trigger arrete_comptable --logical-date 2026-10-27T22:00:00+01:00
```

> En cas d'erreur sur l'option : `airflow dags trigger --help` (le nom des options a changé entre Airflow 2 et 3). Dans l'UI : *Trigger* → choisis la date logique.

Dans l'UI (vue *Grid* et *Graph*), le run attend sur `attendre_fichier` (orange : *up_for_reschedule*). **Le partenaire dépose son fichier** :

```bash
BATCH_DATA=./data bash ../../14-ordonnancement/batch/scripts/generer_transactions.sh 20261027 300
```

Suis la chaîne jusqu'au bout. Ouvre les **logs** de chaque tâche (c'est la *sysout*). Vérifie les sorties :

```bash
ls data/out data/out/partenaire data/archive
cat data/out/reporting_20261027.txt
```

**Calendrier** : lance l'arrêté du **26 décembre 2026** (fermeture TARGET) :

```bash
docker compose exec airflow-scheduler airflow dags trigger arrete_comptable --logical-date 2026-12-26T22:00:00+01:00
```

Toute la chaîne doit être *skipped* (rose). Lis le log de `est_jour_ouvre_target`.

---

## Lab 14.5 — Incidents de nuit : pilote la production (≈ 45 min)

Pour chaque scénario : **observe**, applique tes consignes de pilotage, **remets la chaîne en route**, note l'action Control-M équivalente.

**A. Fichier corrompu**

```bash
BATCH_DATA=./data bash ../../14-ordonnancement/batch/scripts/generer_transactions.sh 20261028 100 corrompu
docker compose exec airflow-scheduler airflow dags trigger arrete_comptable --logical-date 2026-10-28T22:00:00+01:00
```

`controler_fichier` échoue (rc 13) sans relance, l'alerte s'affiche. « Le partenaire renvoie un fichier correct » :

```bash
BATCH_DATA=./data bash ../../14-ordonnancement/batch/scripts/generer_transactions.sh 20261028 100
```

Relance **à partir de la tâche en échec** : dans l'UI, `controler_fichier` → *Clear* (avec *Downstream*). → Control-M : **Rerun**.

**B. Panne pendant le chargement (relances automatiques)**

```bash
touch data/fail_charger_transactions
BATCH_DATA=./data bash ../../14-ordonnancement/batch/scripts/generer_transactions.sh 20261029 100
docker compose exec airflow-scheduler airflow dags trigger arrete_comptable --logical-date 2026-10-29T22:00:00+01:00
```

Observe les tentatives (*up_for_retry*). Pendant la 2ᵉ tentative, « répare » : `rm data/fail_charger_transactions`. La 3ᵉ tentative passe. Le grand livre est-il correct, sans doublon ? (`grep -c ';20261029;' data/work/grand_livre.csv`)

**C. Traitement réalisé à la main**

Le transfert partenaire échoue (`touch data/fail_transferer_partenaire`) et l'équipe envoie le fichier par un autre moyen. Pour que la chaîne continue : *Mark as success* sur la tâche. → Control-M : **Set to OK**. Écris dans ton journal **pourquoi** (traçabilité). Supprime le fichier `fail_…` ensuite.

**D. Ressource : deux arrêtés en concurrence**

Passe `max_active_runs` à 2 dans le DAG, dépose les fichiers du 02/11 et du 03/11, déclenche les deux dates. Dans la vue *Grid*, observe que `charger_transactions` et `calculer_soldes` ne tournent **jamais en même temps** sur les deux runs (pool `db_batch` à 1 place). Dans l'UI : *Admin → Pools* montre les slots occupés. Remets `max_active_runs=1`.

**E. Rattrapage (backfill)**

L'ordonnanceur était arrêté toute la semaine du 19 au 23/10. Dépose les 5 fichiers et rejoue la semaine :

```bash
for d in 20261019 20261020 20261021 20261022 20261023; do
  BATCH_DATA=./data bash ../../14-ordonnancement/batch/scripts/generer_transactions.sh $d 50
done
docker compose exec airflow-scheduler airflow backfill create --dag-id arrete_comptable \
  --from-date 2026-10-19 --to-date 2026-10-23
```

(`airflow backfill --help` si la syntaxe diffère.) Combien de runs ont été créés ? Pourquoi `max_active_runs=1` est-il essentiel ici ?

---

## Lab 14.6 — Dépendance entre chaînes (≈ 15 min)

Crée `dags/reporting_reglementaire.py`, planifié par l'**Asset** publié par `fin_arrete` (`schedule=[ARRETE_TERMINE]`), qui exécute `consolider_reporting.sh`. Déclenche un nouvel arrêté complet : le reporting démarre **tout seul** à la fin. Dans l'UI, menu *Assets* : vois le lien entre les deux DAGs.

→ C'est la **condition** Control-M `ARRETE_COMPTABLE-OK` posée par l'un (`AddEvents`) et attendue par l'autre (`WaitForEvents`).

---

## Lab 14.7 — La même chaîne en Control-M (Jobs-as-Code) (≈ 30 min)

Écris `batch/controlm/ARRETE_COMPTABLE.json` : la même chaîne au format **Control-M Automation API** :

- `Defaults` : `ControlmServer`, `Host`, `RunAs`, `Application`/`SubApplication`, variables `BATCH_DATA` et `SCRIPTS`, une action `If` NOTOK → `Mail` pour tous les jobs ;
- un `Folder` avec `When` jours ouvrés et `FromTime 2200` ;
- `Job:FileWatcher:Create` pour le fichier (`%%$ODATE` = date sur 8 chiffres ; `%%ODATE` = 6 chiffres !) ;
- `Job:Command` pour chaque script ; `Rerun` sur le chargement ; `Resource:Semaphore` `BaseComptable` (quantité 1) sur chargement et soldes ;
- deux objets `Flow` pour la séquence et la branche parallèle ;
- `AddEvents` `ARRETE_COMPTABLE-OK` en fin de chaîne ; un second folder `REPORTING_REGLEMENTAIRE` avec `WaitForEvents` puis `DeleteEvents`.

Vérifie au moins que c'est du JSON valide :

```bash
jq . batch/controlm/ARRETE_COMPTABLE.json > /dev/null && echo "JSON valide"
```

**Si tu as accès à Control-M Workbench** (via ta mission ou un compte client BMC, cf. [github.com/controlm/workbench](https://github.com/controlm/workbench)) :

```bash
docker login https://distribution.bmc.com -u <utilisateur-EPD> -p <token>        # tes identifiants BMC, jamais dans Git
docker run -dt --cpus=4 -m 8g -p 8443:8443 --hostname=workbench --name workbench distribution.bmc.com/ctmem/workbench:<version>
npm install -g <ctm-cli>      # le CLI se télécharge depuis le Workbench lui-même (voir la doc Automation API)
ctm environment workbench::add && ctm environment set workbench
ctm build batch/controlm/ARRETE_COMPTABLE.json     # validation : corrige jusqu'à 0 erreur
ctm run batch/controlm/ARRETE_COMPTABLE.json -i    # exécution interactive dans le Workbench
```

(Il faudra copier les scripts dans le conteneur, dans `/home/workbench/batch/scripts`.) Sinon, compare ton JSON avec [la solution](solutions/batch/controlm/ARRETE_COMPTABLE.json) et la [documentation Automation API — Code Reference](https://controlm.github.io/).

---

## 🏁 Challenge (sans guide)

1. **SLA** : l'arrêté doit être terminé à 5 h. Ajoute une tâche finale qui échoue si l'heure réelle dépasse 05:00 le lendemain de la logical date, et documente comment Control-M le gérerait (SLA Management).
2. **Fin de mois** : ajoute une branche qui ne tourne que le **dernier jour ouvré TARGET du mois** (calcul d'un rapport mensuel). Écris l'équivalent Control-M (calendrier à règles).
3. **CI des définitions** : ajoute au Jenkinsfile (module 06) un stage qui valide les DAGs (`python -c "import ast; …"` ou `airflow dags list-import-errors` dans un conteneur `apache/airflow`) et le JSON Control-M (`jq`) à chaque commit dans `batch/`. C'est le « jobs as code » en vrai.

---

## Nettoyage

```bash
cd ~/devops-bootcamp/batch/airflow && docker compose down -v
```

## ✅ Validation

```bash
make check-14
```
