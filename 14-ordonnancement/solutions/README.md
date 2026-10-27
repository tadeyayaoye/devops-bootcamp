# Solutions du module 14

| Fichier | Contenu |
|---|---|
| `batch/airflow/dags/arrete_comptable.py` | chaîne complète : calendrier TARGET, FileSensor, pool, relances, branche parallèle, Asset de fin |
| `batch/airflow/dags/reporting_reglementaire.py` | chaîne aval déclenchée par l'Asset (= condition Control-M) |
| `batch/controlm/ARRETE_COMPTABLE.json` | la même chose en Control-M Jobs-as-Code |

`./scripts/use-solution.sh 14` les copie dans `batch/` (le dossier `batch/airflow/` doit déjà contenir le `docker-compose.yaml` du lab 14.2).

⚠ Le JSON Control-M n'a pas pu être validé par `ctm build` (pas de Workbench disponible lors de l'écriture). Les noms d'objets suivent la documentation Automation API (`Job:FileWatcher:Create`, `Resource:Semaphore`, `AddEvents`/`WaitForEvents`/`DeleteEvents`, `If`/`Mail`, `Flow`, `Rerun`) ; si `ctm build` signale une erreur, la correction fait partie de l'exercice.
