"""
# Chaîne REPORTING_REGLEMENTAIRE

Déclenchée **par la fin de l'arrêté comptable** (Asset `batch://arrete_comptable/termine`),
et non par une heure : c'est l'équivalent d'une **condition** Control-M posée par une autre chaîne.
"""
from __future__ import annotations

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, Asset

ARRETE_TERMINE = Asset("batch://arrete_comptable/termine")

with DAG(
    dag_id="reporting_reglementaire",
    description="Consolidation réglementaire, après chaque arrêté comptable",
    schedule=[ARRETE_TERMINE],
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Paris"),
    catchup=False,
    default_args={"owner": "prod-batch", "retries": 1},
    tags=["banque", "batch", "reglementaire"],
    doc_md=__doc__,
) as dag:
    BashOperator(
        task_id="consolider_reporting",
        bash_command="/opt/batch/scripts/consolider_reporting.sh",
        env={"BATCH_DATA": "/opt/airflow/data"},
        append_env=True,
    )
