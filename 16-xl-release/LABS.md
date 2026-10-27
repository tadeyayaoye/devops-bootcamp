# Module 16 — Labs XL Release

> ⏱ ~3 h · **Licence d'essai de 7 jours** à partir du premier démarrage : fais tout le module dans la semaine.
> RAM : XL Release demande beaucoup (prévois 3-4 Go). Garde Jenkins (module 06), arrête le cluster kind, SonarQube, Airflow et Zabbix.

---

## Lab 16.1 — Démarrer XL Release (≈ 15 min)

```bash
make ci-up                                     # Jenkins doit tourner (réseau Docker "cicd")
read -rs XLR_ADMIN_PASSWORD && export XLR_ADMIN_PASSWORD     # choisis un mot de passe admin
docker run -d --name xl-release --network cicd \
  -p 127.0.0.1:5516:5516 \
  -e ADMIN_PASSWORD="$XLR_ADMIN_PASSWORD" -e ACCEPT_EULA=Y \
  -v xlr-data:/opt/xebialabs/xl-release-server/repository \
  xebialabs/xl-release:26.3
docker logs -f xl-release                       # attends que le serveur soit démarré (1-3 min)
```

Ouvre http://localhost:5516 (admin / ton mot de passe). Branché sur le réseau `cicd`, XL Release joint Jenkins par `http://jenkins:8080`.

> Une version plus récente que 26.3 est sortie ? Utilise-la ; si le chemin du volume a changé, consulte la page *Use the Release Docker images*. Le volume sert à ne pas perdre ton travail si tu recrées le conteneur (pendant les 7 jours de licence).

---

## Lab 16.2 — Organisation : dossier, équipes, séparation des tâches (≈ 20 min)

1. *Settings → Users* : crée deux utilisateurs, `dev1` (développeur) et `cab1` (approbateur CAB).
2. Crée un **folder** `Banque` › `taskapi`.
3. Dans le folder, *Teams* : `Developpeurs` (dev1 : créer et démarrer des releases, réaliser des tâches) et `Approbateurs CAB` (cab1 : réaliser les gates de production). Garde `admin` pour l'administration.
4. *Connections* (*Shared configuration*) → **Jenkins: Server** : nom `Jenkins bootcamp`, URL `http://jenkins:8080`, utilisateur `admin`, mot de passe = un **API token Jenkins** (Jenkins → ton profil → *Security → API Token → Add new token*). Bouton *Test*.

---

## Lab 16.3 — Le template « Livraison taskapi » (≈ 50 min)

Dans le folder `taskapi`, crée le template **Livraison taskapi** avec ces variables :
`${version}` (texte, obligatoire : le tag d'image, ex. `1a2b3c4`), `${rfc}` (texte, obligatoire), `${demandeur}` (texte).

Et ces phases :

**1. Préparation**
- *Manual* — « Vérifier que la RFC ${rfc} est approuvée en CAB » (équipe `Developpeurs`).
- *Gate* — « Hors période de gel ? » (condition à cocher).

**2. Build & qualité**
- *Jenkins: Build* — serveur `Jenkins bootcamp`, job `taskapi/main` (multibranch ; si XLR ne le trouve pas, essaie `taskapi/job/main`). Mappe le numéro de build dans une variable `${buildNumber}`.
- *Gate* — « Quality gate SonarQube OK et 0 CVE CRITICAL (build #${buildNumber}) ».

**3. Recette (dev)**
- *Manual* — « Vérifier `curl http://taskapi-dev.localhost/version` = ${version} » (en vrai : une tâche HTTP automatique).
- *Notification* — « Version ${version} disponible en recette » (adresse fictive).

**4. Validation (go / no-go)**
- *Gate* — « GO PROD — validation CAB pour ${rfc} », **assignée à l'équipe `Approbateurs CAB`**.

**5. Production**
- *Manual* — « Créer la maintenance Zabbix » (ou le challenge 2 pour l'automatiser).
- *Manual* — « Lancer `08-gitops-argocd/scripts/promote.sh ${version}` et merger la PR » (ou le challenge 1).
- *Manual* — « Tests post-MEP : `/readyz`, dashboard Grafana, aucune alerte ».

**6. Clôture**
- *Notification* — « MEP ${version} terminée (RFC ${rfc}) ».
- *Manual* — « Clôturer la RFC ${rfc} ».

---

## Lab 16.4 — Exécuter une MEP, comme en vrai (≈ 35 min)

1. Connecte-toi en **dev1**, démarre une release depuis le template : titre `MEP taskapi <version>`, variables renseignées (prends le tag actuellement en dev : `yq '.images[0].newTag' ~/devops-bootcamp-gitops/envs/dev/kustomization.yaml`).
2. Avance : la tâche Jenkins lance réellement un build (vérifie dans Jenkins) et attend son résultat.
3. Arrivé à la gate **GO PROD** : en dev1, essaie de la valider → impossible (**séparation des tâches**). Déconnecte-toi, connecte-toi en **cab1**, valide avec un commentaire.
4. Termine la release.
5. Ouvre la **timeline** de la release, puis l'**audit** / le rapport : qui a fait quoi, quand, combien de temps chaque phase a duré.

**Gérer un échec** : relance une release, et pendant le build Jenkins, fais-le échouer (par ex. arrête Jenkins quelques secondes : `docker stop jenkins && sleep 20 && docker start jenkins`, ou pousse une branche qui casse les tests). La tâche Jenkins passe en échec : essaie **Retry**, puis **Skip** (un commentaire est exigé : pourquoi ?). Termine par **Abort**.

---

## Lab 16.5 — Gel des MEP (≈ 15 min)

*Release calendar* (ou *Plan* selon la version) → crée une **blackout period** « Gel arrêté comptable » sur les 2 prochains jours. Planifie une release (date de démarrage dans la période) et observe comment XL Release le signale. Compare avec les *sync windows* d'Argo CD (module 08).

---

## Lab 16.6 — As code : exporter, versionner, réimporter (≈ 30 min)

1. Exporte ton template en YAML (menu du template → *Export* / *Release as code*), enregistre-le dans `release/xlr/livraison-taskapi.yaml` et commite-le.
2. Installe le CLI `xl` (lien de téléchargement pour Linux dans la documentation Digital.ai, section *Install the XL CLI* ; place le binaire dans `/usr/local/bin`), puis :

```bash
xl version
cat > ~/.xebialabs/config.yaml <<EOF
xl-release:
  url: http://localhost:5516/
  username: admin
  password: ${XLR_ADMIN_PASSWORD}
EOF
chmod 600 ~/.xebialabs/config.yaml
```

3. Modifie le YAML (ajoute une tâche *Manual* « Prévenir le support N1 » dans la phase Production), puis :

```bash
xl apply -f release/xlr/livraison-taskapi.yaml
```

Vérifie dans l'UI que le template a été mis à jour. La définition du processus de MEP est maintenant **dans Git**, revue en PR comme le reste.

---

## Lab 16.7 — Démarrer une release depuis la CI, par l'API (≈ 15 min)

```bash
XLR="http://localhost:5516"
curl -fsS -u "admin:$XLR_ADMIN_PASSWORD" "$XLR/api/v1/templates" | jq -r '.[] | "\(.id)  \(.title)"'
TEMPLATE_ID="<id du template Livraison taskapi>"
curl -fsS -u "admin:$XLR_ADMIN_PASSWORD" -X POST -H 'Content-Type: application/json' \
  "$XLR/api/v1/templates/$TEMPLATE_ID/start" \
  -d '{"releaseTitle":"MEP taskapi (API)","variables":{"version":"test","rfc":"RFC-API-1","demandeur":"jenkins"}}' | jq '{id, title, status}'
```

Réfléchis : à quel endroit du Jenkinsfile (module 08) mettrais-tu cet appel ? Avec quel identifiant (credential Jenkins dédié, droits limités au démarrage de releases) ?

---

## 🏁 Challenge (sans guide)

1. **Promotion GitOps automatique** : remplace la tâche manuelle de promotion par un **job Jenkins** paramétré `promote-prod` (qui exécute l'équivalent de `promote.sh ${VERSION}`) déclenché par une tâche *Jenkins: Build* — la PR GitOps est créée par la release, et une gate attend son merge.
2. **Maintenance Zabbix automatique** : une tâche *Webhook / HTTP Request* (ou *Script*) qui appelle `maintenance.create` sur l'API Zabbix (module 15) avant la production, et une autre qui la supprime en clôture. Token Zabbix dans une variable de type *password*.
3. **Hold du batch** : décris (ou réalise si tu as un Workbench Control-M) la tâche qui met en *Hold* le folder `ARRETE_COMPTABLE` pendant la MEP puis le libère (plugin Control-M de Digital.ai Release, ou appel de l'Automation API `ctm run job::hold`).

---

## Nettoyage

```bash
docker rm -f xl-release && docker volume rm xlr-data
```

## ✅ Validation

```bash
make check-16
```
