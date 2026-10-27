"""
# Chaîne ARRETE_COMPTABLE

Arrêté comptable de fin de journée, **les jours ouvrés TARGET**, à partir de 22 h (Europe/Paris).

| Étape | Rôle | Équivalent Control-M |
|---|---|---|
| `est_jour_ouvre_target` | saute la chaîne les week-ends et jours de fermeture TARGET | calendrier |
| `attendre_fichier` | attend le fichier du partenaire (2 h max) | File Watcher |
| `controler_fichier` | totaux de contrôle — **pas de relance auto** | Job:Command |
| `charger_transactions` | grand livre, **pool `db_batch`** (1 place) | ressource quantitative |
| `calculer_soldes` | soldes à date, pool `db_batch` | ressource quantitative |
| `generer_reporting` / `transferer_partenaire` | en parallèle | Flow |
| `archiver` | archivage + purge | |
| `fin_arrete` | publie l'Asset qui déclenche le reporting réglementaire | AddEvents (condition) |

Consignes de pilotage : voir `13-contexte-bancaire/livrables/consignes-ARRETE_COMPTABLE.md`.
"""
from __future__ import annotations

from datetime import date, timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.empty import EmptyOperator
from airflow.providers.standard.operators.python import ShortCircuitOperator
from airflow.providers.standard.sensors.filesystem import FileSensor
from airflow.sdk import DAG, Asset

SCRIPTS = "/opt/batch/scripts"
DATA = "/opt/airflow/data"
ODATE = "{{ ds_nodash }}"          # la date d'ordonnancement (logical date) au format AAAAMMJJ = %%ODATE
ARRETE_TERMINE = Asset("batch://arrete_comptable/termine")


# ----------------------------------------------------------------------------- calendrier
def paques(annee: int) -> date:
    """Dimanche de Pâques (algorithme de Meeus/Jones/Butcher, calendrier grégorien)."""
    a, b, c = annee % 19, annee // 100, annee % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7  # noqa: E741
    m = (a + 11 * h + 22 * l) // 451
    mois = (h + l - 7 * m + 114) // 31
    jour = (h + l - 7 * m + 114) % 31 + 1
    return date(annee, mois, jour)


def jours_fermeture_target(annee: int) -> set[date]:
    """Jours de fermeture du système de paiement européen TARGET."""
    p = paques(annee)
    return {
        date(annee, 1, 1),            # Jour de l'an
        p - timedelta(days=2),        # Vendredi saint
        p + timedelta(days=1),        # Lundi de Pâques
        date(annee, 5, 1),            # Fête du travail
        date(annee, 12, 25),          # Noël
        date(annee, 12, 26),          # Lendemain de Noël
    }


def est_jour_ouvre_target(logical_date=None, **_) -> bool:
    jour = (logical_date or pendulum.now("Europe/Paris")).in_timezone("Europe/Paris").date()
    ouvre = jour.weekday() < 5 and jour not in jours_fermeture_target(jour.year)
    print(f"Date d'ordonnancement {jour} : {'jour ouvré TARGET' if ouvre else 'jour FERMÉ → chaîne sautée'}")
    return ouvre


# ----------------------------------------------------------------------------- alerting
def alerter(context) -> None:
    """Appelé quand une tâche échoue définitivement (après ses relances). En vrai : ticket, mail, pager."""
    ti = context["task_instance"]
    print(f"🚨 ALERTE BATCH : {ti.dag_id}.{ti.task_id} en échec pour le {context['ds']} "
          f"(tentative {ti.try_number}) — consulter les consignes de pilotage")


def job(task_id: str, script: str, **kwargs) -> BashOperator:
    """Un job batch = un script, la date en argument, le code retour comme verdict."""
    return BashOperator(
        task_id=task_id,
        bash_command=f"{SCRIPTS}/{script} {ODATE}",
        env={"BATCH_DATA": DATA},
        append_env=True,
        **kwargs,
    )


with DAG(
    dag_id="arrete_comptable",
    description="Arrêté comptable de fin de journée (jours ouvrés TARGET)",
    schedule="0 22 * * 1-5",
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Paris"),
    catchup=False,
    max_active_runs=1,                  # jamais deux arrêtés en même temps
    default_args={
        "owner": "prod-batch",
        "retries": 1,
        "retry_delay": timedelta(minutes=2),
        "on_failure_callback": alerter,
    },
    tags=["banque", "batch", "arrete"],
    doc_md=__doc__,
) as dag:
    jour_ouvre = ShortCircuitOperator(task_id="est_jour_ouvre_target", python_callable=est_jour_ouvre_target)

    attendre_fichier = FileSensor(
        task_id="attendre_fichier",
        fs_conn_id="fs_batch",
        filepath=DATA + "/in/transactions_" + ODATE + ".csv",
        poke_interval=30,
        timeout=2 * 60 * 60,            # au-delà de 2 h sans fichier : échec → appel du partenaire
        mode="reschedule",              # libère le worker entre deux vérifications
    )

    controler = job("controler_fichier", "controler_fichier.sh", retries=0)
    charger = job("charger_transactions", "charger_transactions.sh", pool="db_batch", retries=2)
    soldes = job("calculer_soldes", "calculer_soldes.sh", pool="db_batch")
    reporting = job("generer_reporting", "generer_reporting.sh")
    transfert = job("transferer_partenaire", "transferer_partenaire.sh")
    archiver = job("archiver", "archiver.sh")
    fin = EmptyOperator(task_id="fin_arrete", outlets=[ARRETE_TERMINE])

    jour_ouvre >> attendre_fichier >> controler >> charger >> soldes >> [reporting, transfert] >> archiver >> fin
