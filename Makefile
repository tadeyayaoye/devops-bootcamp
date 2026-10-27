# Raccourcis du bootcamp. `make help` pour la liste.
# Chaque cible affiche la vraie commande exécutée : le but est que tu saches la retaper sans make.

SHELL       := /usr/bin/env bash
CLUSTER     ?= bootcamp
GITOPS_DIR  ?= $(abspath ../devops-bootcamp-gitops)
TF_DIR      := infra/terraform
CI_COMPOSE  := docker compose -f ci/compose.yaml

.DEFAULT_GOAL := help

## —— Général ———————————————————————————————————————————————
help: ## Affiche cette aide
	@grep -hE '^[a-zA-Z0-9_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

tools: ## Vérifie que tous les outils sont installés
	@./scripts/check-tools.sh

check-%: ## Vérifie un module : make check-01
	@bash $(firstword $(wildcard $*-*/check.sh))

solution-%: ## Copie les solutions d'un module sans écraser : make solution-03
	@./scripts/use-solution.sh $*

status: ## État global : conteneurs, cluster, applis Argo
	@echo "== Conteneurs Docker =="; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
	@echo; echo "== Cluster kind =="; kind get clusters 2>/dev/null || true
	@kubectl get nodes 2>/dev/null || true
	@echo; echo "== Applications Argo CD =="; kubectl get applications -n argocd 2>/dev/null || true
	@echo; echo "== Mémoire WSL =="; free -h

## —— Application locale ———————————————————————————————————————
app-venv: ## Crée le venv Python de l'app et installe les dépendances de dev
	cd app && python3 -m venv .venv && . .venv/bin/activate && pip install -q -r requirements-dev.txt

app-test: ## Lance lint + tests de l'app
	cd app && . .venv/bin/activate && ruff check . && pytest --cov --cov-report=term-missing

app-run: ## Lance l'app en local avec SQLite (http://localhost:8000/docs)
	cd app && . .venv/bin/activate && DATABASE_URL=sqlite:///./taskapi.db CHAOS_ENABLED=true \
		PYTHONPATH=src uvicorn taskapi.main:create_app --factory --reload --port 8000

load: ## Génère du trafic : make load URL=http://taskapi-dev.localhost
	python3 scripts/load.py $(or $(URL),http://taskapi-dev.localhost) --duration 120 --concurrency 5

## —— Cluster (avant Terraform : modules 02-03) ——————————————————
cluster-up: ## Crée le cluster kind « à la main » (modules 02-03)
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config 02-kubernetes-bases/kind/kind-config.yaml
	kubectl cluster-info --context kind-$(CLUSTER)

cluster-down: ## Supprime le cluster kind
	kind delete cluster --name $(CLUSTER)

## —— Terraform (à partir du module 04) ——————————————————————————
tf-cluster: ## Crée le cluster via Terraform
	terraform -chdir=$(TF_DIR)/cluster init -upgrade
	terraform -chdir=$(TF_DIR)/cluster apply -auto-approve

tf-platform: ## Installe la plateforme (Traefik, Gateway, metrics-server, Argo CD) via Terraform
	terraform -chdir=$(TF_DIR)/platform init -upgrade
	terraform -chdir=$(TF_DIR)/platform apply -auto-approve

tf-destroy: ## Détruit le cluster via Terraform (le state platform se réalignera au prochain apply)
	terraform -chdir=$(TF_DIR)/cluster destroy -auto-approve

## —— GitOps (à partir du module 08) ——————————————————————————————
gitops-bootstrap: ## Applique l'Application racine (app-of-apps)
	kubectl apply -f $(GITOPS_DIR)/bootstrap/root.yaml

argocd-password: ## Affiche le mot de passe admin initial d'Argo CD
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

SEALED_KEY_BACKUP ?= $(HOME)/.bootcamp/sealed-secrets-key.yaml

sealed-key-backup: ## Sauvegarde la clé privée Sealed Secrets HORS du repo (avant de détruire le cluster)
	@mkdir -p $(dir $(SEALED_KEY_BACKUP)) && umask 077 && \
	kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > $(SEALED_KEY_BACKUP) && \
	echo "Clé sauvegardée dans $(SEALED_KEY_BACKUP) (secret : ne jamais commiter)" || echo "Pas de clé à sauvegarder"

sealed-key-restore: ## Restaure la clé Sealed Secrets (avant le bootstrap GitOps)
	@if [ -s $(SEALED_KEY_BACKUP) ]; then kubectl apply -f $(SEALED_KEY_BACKUP) && echo "Clé restaurée"; \
	else echo "Aucune sauvegarde de clé : les SealedSecret devront être re-scellés"; fi

## —— CI (à partir du module 06) ——————————————————————————————————
ci-up: ## Démarre Jenkins
	$(CI_COMPOSE) up -d --build jenkins

sonar-up: ## Démarre SonarQube (+ sa base)
	$(CI_COMPOSE) --profile sonar up -d sonarqube sonar-db

sonar-down: ## Arrête SonarQube (libère ~3 Go)
	$(CI_COMPOSE) --profile sonar stop sonarqube sonar-db

ci-down: ## Arrête toute la CI
	$(CI_COMPOSE) --profile sonar down

## —— Tout-en-un (module 11) ———————————————————————————————————————
up: tf-cluster tf-platform sealed-key-restore gitops-bootstrap urls ## Reconstruit tout : cluster + plateforme + GitOps

down: sealed-key-backup ci-down tf-destroy ## Détruit tout (cluster + CI). Les volumes Docker de la CI sont conservés.

urls: ## Affiche les URLs utiles
	@echo "taskapi dev   : http://taskapi-dev.localhost"
	@echo "taskapi prod  : http://taskapi.localhost"
	@echo "Argo CD       : http://argocd.localhost   (admin / make argocd-password)"
	@echo "Grafana       : http://grafana.localhost  (admin / bootcamp)"
	@echo "Prometheus    : http://prometheus.localhost"
	@echo "Alertmanager  : http://alertmanager.localhost"
	@echo "Jenkins       : http://localhost:8080"
	@echo "SonarQube     : http://localhost:9000"
	@echo "Airflow       : http://localhost:8090     (airflow / airflow)"
	@echo "Zabbix        : http://localhost:8091     (Admin / à changer)"
	@echo "XL Release    : http://localhost:5516     (admin / ton mot de passe)"

## —— Parcours banque (modules 14-16) ——————————————————————————————
airflow-up: ## Démarre Airflow (module 14, batch/airflow doit être initialisé)
	cd batch/airflow && docker compose up -d

airflow-down: ## Arrête Airflow
	cd batch/airflow && docker compose down

zabbix-up: ## Démarre le labo Ansible puis Zabbix (module 15)
	docker compose -f 05-ansible/lab/compose.yaml up -d
	docker compose -f 15-zabbix/lab/compose.yaml up -d

zabbix-down: ## Arrête Zabbix (garde ses données)
	docker compose -f 15-zabbix/lab/compose.yaml down

xlr-down: ## Arrête XL Release (le volume xlr-data est conservé)
	docker rm -f xl-release

.PHONY: help tools status app-venv app-test app-run load cluster-up cluster-down tf-cluster tf-platform \
	tf-destroy gitops-bootstrap argocd-password sealed-key-backup sealed-key-restore ci-up sonar-up sonar-down ci-down up down urls \
	airflow-up airflow-down zabbix-up zabbix-down xlr-down
