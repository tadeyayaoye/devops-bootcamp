# Module 11 — Projet final

> ⏱ ~6 h · Note les heures de début/fin de chaque phase dans `11-projet-final/JOURNAL.md` : ce sont tes métriques.

---

## Phase 0 — Préparation (15 min)

```bash
cd ~/devops-bootcamp && git pull
cd ~/devops-bootcamp-gitops && git pull
cd ~/devops-bootcamp
make status
```

Crée `11-projet-final/JOURNAL.md` avec un tableau : phase · début · fin · durée · remarques.

---

## Phase 1 — Tout détruire, tout reconstruire (≈ 1 h)

```bash
make sealed-key-backup
make down                          # CI arrêtée + cluster détruit
docker ps                          # plus rien (à part éventuellement le labo Ansible)
```

Chronomètre la reconstruction **complète** :

```bash
time make up                       # cluster + plateforme (Terraform) + clé + bootstrap GitOps
make ci-up && make sonar-up
```

Attends que tout soit vert :

```bash
kubectl -n argocd get applications -w      # toutes Synced/Healthy ? lesquelles traînent et pourquoi ?
make urls
```

Vérifie : http://taskapi-dev.localhost, http://taskapi.localhost, Grafana (dashboards et datasources présents), Argo CD, Jenkins (job présent), SonarQube (mot de passe et token conservés grâce aux volumes ? sinon relance `ci/scripts/sonar-setup.sh`).

**Question à noter** : qu'est-ce qui n'est PAS revenu tout seul ? (données Postgres, historique Prometheus, traces… ⇒ ce qu'il faudrait sauvegarder/externaliser en vrai : Velero, stockage objet, base managée.)

---

## Phase 2 — Livrer une fonctionnalité de bout en bout (≈ 1 h 30)

**Besoin métier** : un endpoint `GET /api/tasks/stats` qui renvoie `{"total": n, "done": n, "todo": n}`.

1. Issue GitHub (`gh issue create -l "type: feature"`), branche `feat/stats`.
2. Code + **tests** (couverture du nouveau code ≥ 80 % : sinon la quality gate bloque).
3. PR (`gh pr create`) : le workflow GitHub Actions tourne sur la PR, Jenkins construit la branche. Tout doit être vert.
4. Merge (squash) → Jenkins sur `main` : image publiée, commit du bot dans `envs/dev`.
5. Argo CD déploie en dev → teste `curl http://taskapi-dev.localhost/api/tasks/stats`.
6. Vérifie dans Grafana que la nouvelle route apparaît dans « Trafic par route », et dans Tempo qu'une trace existe.
7. **Promotion** : `08-gitops-argocd/scripts/promote.sh` → revue de la PR GitOps → merge → prod.

Mesure le **lead time** commit → dev, et merge de la PR de promotion → prod.

---

## Phase 3 — Quatre incidents (≈ 2 h)

Pour chacun : note l'heure de début, **détecte** (alerte ? dashboard ? Argo ?), **mitige**, mesure MTTD/MTTR, puis un mini-postmortem (5 lignes) dans le journal.

### Incident A — Le mauvais déploiement

Sur une branche, introduis un bug qui **passe les tests** mais casse la readiness en environnement réel. Exemple : dans `routes.py`, faire échouer `/readyz` quand `APP_ENV` vaut `dev` ou `prod` (un test unitaire ne le verra pas, l'env de test étant `test`). Merge, laisse la chaîne déployer en dev.

Attendu : nouveaux pods jamais Ready, **anciens pods toujours en service** (`maxUnavailable: 0`), Argo CD `Progressing` puis `Degraded`. Mitigation : `git revert` (dans quel repo ? les deux options sont défendables : explique ton choix).

### Incident B — La CVE critique

Ajoute `pyyaml==5.3` aux dépendances et pousse sur une branche. Attendu : le **gate Trivy bloque** le pipeline avant toute publication. Que serait-il arrivé sans ce gate ? Comment gérerais-tu une CVE critique **sans correctif** disponible (exception documentée, mitigation, surveillance) ?

### Incident C — La panne de production

```bash
NS=taskapi-prod bash 10-logs-traces-slo/labs/incident.sh 1     # erreurs 5xx injectées en PROD
```

Attendu : alertes `TaskapiHighErrorRate` puis burn rate, dashboard SLO qui plonge. Investigation logs → traces. Mitigation la plus rapide ? Combien de budget d'erreur consommé ?

### Incident D — La surprise

Lance `bash 10-logs-traces-slo/labs/incident.sh` (scénario aléatoire) **sans regarder lequel**. Rédige le postmortem complet dans `10-logs-traces-slo/postmortems/` avec le modèle.

---

## Phase 4 — Exploitation et nettoyage (≈ 30 min)

1. Mets à jour une version de chart (ex. Traefik) **par GitOps ou Terraform**, en lisant le changelog avant. Plan, apply, vérification.
2. Rotation de secret : régénère le mot de passe Postgres de **dev** (re-scelle), et gère le fait que Postgres a déjà un mot de passe (supprime le PVC en dev, ou `ALTER USER` via un Job). Raconte la procédure qu'il faudrait en prod.
3. Archive ton travail : `git tag -a bootcamp-final -m "Fin du bootcamp"` sur les deux repos, `git push --tags`.

---

## Grille d'auto-évaluation du projet final

| Critère | ✔ |
|---|---|
| Reconstruction complète en < 30 min sans intervention manuelle hors commandes `make` | |
| Fonctionnalité livrée de l'issue à la prod en suivant tout le processus | |
| Incident A détecté par Argo CD et sans impact utilisateur grâce à la stratégie de rollout | |
| Incident B bloqué par la CI avant publication | |
| Incident C détecté par une alerte avant que tu ne regardes le dashboard | |
| Incident D diagnostiqué sans lire le script, postmortem rédigé | |
| Pitch de 5 min enregistré (audio) et réécouté | |

---

## ✅ Validation finale

```bash
make check-11
```
