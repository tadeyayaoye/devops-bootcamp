# Module 13 — Le DevOps en milieu bancaire : contexte, contraintes, vocabulaire

> **Objectif** : comprendre **dans quel monde** s'inscrivent Control-M, Zabbix et XL Release, pour être crédible dès le premier entretien de mission : organisation de la production, processus ITIL, réglementation, vocabulaire des équipes.
>
> **Durée** : cours ~1 h 30 · exercices ~1 h 30 · quiz 30 min · *Parcours complémentaire « banque », à faire avant les modules 14 à 16.*

---

## 1. Pourquoi la banque est différente

Une banque fait tourner, en même temps :
- du **très ancien** : mainframe IBM z/OS (COBOL, JCL, DB2, CICS), serveurs AIX/Solaris, traitements batch écrits il y a 30 ans ;
- du **classique** : VM Linux/Windows, Oracle, middleware (MQ, Tomcat, WebSphere), échanges de fichiers ;
- du **moderne** : conteneurs (très souvent **OpenShift**), CI/CD, cloud (de plus en plus de cloud privé ou « de confiance »).

Et elle le fait sous des contraintes fortes :

| Contrainte | Conséquence pour toi |
|---|---|
| **Réglementation** (BCE, ACPR, EBA, règlement DORA…) | tout doit être tracé, justifié, auditable |
| **Argent des clients** | une erreur = des virements faux, des soldes faux → tolérance quasi nulle |
| **Disponibilité** | paiements par carte 24/7, virements instantanés |
| **Fenêtres batch** | la nuit, les traitements de fin de journée doivent finir avant l'ouverture |
| **Sécurité** | cloisonnement réseau, comptes à privilèges contrôlés (CyberArk…), pas d'accès direct à la prod |
| **Taille** | des milliers d'applications, des dizaines de milliers de jobs par nuit |

Le DevOps en banque, c'est donc **automatiser et accélérer… sans jamais perdre le contrôle ni la traçabilité**. Les outils des modules 14-16 existent pour ça.

---

## 2. L'organisation de la production

### Les environnements

```
DEV  →  INT (intégration)  →  REC / QUAL (recette, qualification)  →  PRÉPROD / HOMOL (homologation)  →  PROD
                                                                                       ↑
                                                                         copie au plus près de la prod
```

- Chaque passage est une **promotion** (comme dev → prod au module 08, en plus d'étapes).
- **Le même livrable** est promu d'un environnement à l'autre : c'est exactement *build once, deploy many*.
- La recette est souvent faite par des **équipes métier** (MOA) qui valident fonctionnellement.

### Les métiers (vocabulaire à connaître)

| Terme | Rôle |
|---|---|
| **MOA / MOE** | maîtrise d'ouvrage (le métier, qui exprime le besoin) / maîtrise d'œuvre (les équipes qui construisent) |
| **Ingénieur de production / d'exploitation** (« prod », « run ») | exploite les applications en production : MEP, supervision, incidents, batch |
| **Pilote / opérateur** (« pupitreur » historiquement) | surveille la production 24/7, notamment le **plan de production** batch, et applique les consignes |
| **Ordonnanceur** (le métier) | conçoit et maintient les chaînes batch dans l'outil d'ordonnancement |
| **Équipe d'astreinte** | intervient hors heures ouvrées sur incident |
| **Support N1 / N2 / N3** | N1 : centre de services / pilotage ; N2 : prod applicative ; N3 : experts / développeurs / éditeurs |
| **Build / Run** | construire (projets) / faire tourner (exploitation) — le DevOps vise à rapprocher les deux |
| **SRE** | approche Google : la fiabilité traitée comme un problème d'ingénierie (SLO, budget d'erreur, automatisation) |

### La séparation des tâches

Principe d'audit fondamental : **celui qui développe ne déploie pas seul en production**. Concrètement :
- les développeurs n'ont pas d'accès en écriture à la prod ;
- une mise en production passe par un **changement approuvé** ;
- les actions sur la prod sont faites par des comptes nominatifs ou des outils tracés (XL Release, Ansible Automation Platform, Control-M…).

Le DevOps ne supprime pas ce principe : il le **déplace dans l'outillage**. Par exemple, une PR GitOps vers `envs/prod` approuvée par une autre personne, puis un déploiement automatique, journalisé et réversible : c'est une séparation des tâches plus forte qu'un humain qui tape des commandes en prod.

---

## 3. ITIL : les processus de la production

ITIL (v4 aujourd'hui) est le référentiel des bonnes pratiques de gestion des services IT. En banque, il est **partout**, souvent outillé par **ServiceNow**.

| Processus | En bref | Lien avec tes outils |
|---|---|---|
| **Gestion des incidents** | rétablir le service au plus vite | alertes Zabbix → ticket incident automatique |
| **Gestion des problèmes** | trouver et éliminer la cause racine des incidents récurrents | postmortem (module 10) |
| **Gestion des changements** | évaluer, approuver, planifier toute modification de la prod | **RFC** + **CAB** ; XL Release porte le circuit d'approbation |
| **Gestion des mises en production** (release) | assembler, tester, livrer un ensemble de changements | XL Release orchestre la MEP |
| **Gestion des configurations** (CMDB) | inventaire des composants et de leurs dépendances | une alerte Zabbix est rattachée à un élément de configuration (CI) |
| **Gestion des événements** | surveiller et filtrer les événements | Zabbix, corrélation |
| **Gestion de la capacité / disponibilité / continuité** | anticiper, mesurer, garantir | tendances Zabbix, PCA/PRA |

### Le changement, en détail

- **RFC** (*Request For Change*) : la demande, avec la description, l'impact, le plan de déploiement, le **plan de retour arrière** (rollback), le plan de test et la fenêtre d'intervention.
- Types de changements :
  - **standard** : pré-approuvé, répétitif, faible risque (ex. un déploiement via la chaîne automatisée validée) → c'est là que le DevOps fait gagner du temps ;
  - **normal** : passe en **CAB** (*Change Advisory Board*, réunion d'approbation hebdomadaire) ;
  - **urgent** : correctif d'incident, circuit accéléré (*ECAB*).
- **Gel des changements** (*freeze*) : périodes sans MEP (fin d'année, arrêtés comptables, opérations exceptionnelles).
- **Fenêtre de MEP** : souvent la nuit ou le week-end, hors batch critique.

> 💡 En entretien, savoir dire « je rattache chaque déploiement à une RFC, avec un plan de rollback testé » est très apprécié. Et savoir dire « un pipeline fiable permet de classer les déploiements en **changement standard** » montre que tu comprends la valeur du DevOps pour la banque.

---

## 4. Le batch : le cœur historique de la banque

Toute la journée, la banque enregistre des opérations. La nuit, des **chaînes batch** les traitent :

```
22:00  Arrêté de la journée comptable
22:05  ├─ réception des fichiers partenaires (cartes, compensation, SWIFT…)   ← dépendance externe : on attend le fichier
22:30  ├─ contrôles (format, nombre d'enregistrements, totaux de contrôle)
23:00  ├─ intégration dans la comptabilité, calcul des soldes, des intérêts
01:00  ├─ éditions, reporting réglementaire, alimentation de l'entrepôt de données
03:00  ├─ envois de fichiers (échanges interbancaires, régulateur) via un outil de transfert (MFT : CFT, Axway, Control-M MFT…)
05:00  ├─ sauvegardes, purges
06:30  └─ « ouverture » : les applications de jour doivent trouver des données à jour
```

Notions clés (détaillées au module 14) : **plan de production**, **date comptable / date d'ordonnancement**, **dépendances** (conditions), **ressources** (limiter les accès concurrents à une base), **calendriers** (jours ouvrés, fériés, fin de mois), **reprise** (relancer à partir d'une étape), **SLA batch** (la chaîne doit être finie à 6 h 30).

Les outils : **Control-M** (BMC, le plus répandu), **$Universe** (Dollar Universe, Broadcom, très présent en France), **VTOM** (Absyss, éditeur français), **Autosys** (Broadcom), **IBM Workload Scheduler** (ex-TWS), et côté open source **Airflow**, **JS7 JobScheduler**, **Rundeck**. Beaucoup de banques migrent vers Control-M, ou vers des outils plus « cloud ».

---

## 5. Réglementation : ce qu'il faut savoir citer

| Texte | Ce qu'il impose (en résumé) |
|---|---|
| **DORA** (*Digital Operational Resilience Act*, règlement UE 2022/2554, applicable depuis le **17 janvier 2025**) | gestion des risques TIC, **déclaration des incidents majeurs** au régulateur sous des délais stricts, **tests de résilience** (dont tests d'intrusion TLPT), gestion des **prestataires tiers** (cloud…), partage d'information sur les menaces |
| **PCI DSS** | sécurité des données de cartes de paiement (chiffrement, cloisonnement, journalisation, gestion des vulnérabilités) |
| **RGPD** | données personnelles : minimisation, droit à l'effacement, pas de données de prod en recette sans anonymisation |
| Exigences ACPR / BCE / EBA (guidelines sur le risque TIC et la sécurité) | gouvernance, continuité, externalisation |
| Normes : **ISO 27001** (sécurité), **SOC 2** / ISAE 3402 (contrôles des prestataires) | |

⚠ **Ne confonds pas** : **DORA le règlement** (résilience opérationnelle) et **les métriques DORA** du module 06 (*DevOps Research and Assessment* : fréquence de déploiement, lead time…). Même sigle, sujets différents… mais liés : un bon outillage DevOps aide à respecter le règlement (traçabilité, tests, gestion d'incident).

Conséquences pratiques pour un DevOps :
- **Traçabilité de bout en bout** : du commit à la MEP (qui, quoi, quand, approuvé par qui).
- **Journaux conservés et protégés** (durées de rétention réglementaires).
- **Gestion des vulnérabilités** documentée (le scan Trivy et sa politique d'exceptions du module 07).
- **Continuité** : **PCA** (plan de continuité d'activité) et **PRA** (plan de reprise d'activité), avec des objectifs **RTO** (durée maximale d'interruption) et **RPO** (perte de données maximale acceptable), **testés** régulièrement (le module 08 lab 8.7 en est une mini-version).

---

## 6. L'outillage typique d'une banque (2026)

| Besoin | Outils fréquents |
|---|---|
| Code, CI | GitLab, Bitbucket, GitHub Enterprise ; **Jenkins** (très présent), GitLab CI |
| Qualité, sécurité | **SonarQube**, Checkmarx, Fortify, Nexus IQ, Trivy, Xray |
| Artefacts | **Nexus**, **Artifactory** (dépôts internes, aucun téléchargement direct depuis Internet) |
| Orchestration des MEP | **XL Release / XL Deploy** (Digital.ai), ServiceNow DevOps, scripts maison |
| Ordonnancement | **Control-M**, $Universe, VTOM, Autosys |
| Supervision | **Zabbix**, Centreon, Nagios, Dynatrace, AppDynamics, Prometheus/Grafana sur les plateformes conteneurs |
| Logs | **Splunk**, ELK/OpenSearch, Loki |
| ITSM | **ServiceNow** |
| Conteneurs | **OpenShift** (souvent), Kubernetes managé |
| Configuration | **Ansible** / Ansible Automation Platform, Puppet, Terraform |
| Secrets, comptes à privilèges | HashiCorp Vault, **CyberArk** |
| Transfert de fichiers | **CFT** (Axway), Control-M MFT, Connect:Direct |

Les modules 14 à 16 te donnent les bases de **Control-M**, **Zabbix** et **XL Release** ; le reste du bootcamp couvre Jenkins, SonarQube, Ansible, Terraform, Kubernetes et le GitOps.

---

## 7. Les livrables du quotidien

En mission, on te demandera aussi d'**écrire** :
- un **dossier d'exploitation** (DEX) : architecture, flux, procédures de démarrage/arrêt, sauvegardes, supervision, consignes de reprise ;
- des **consignes de pilotage** pour les jobs batch (que faire si tel job plante à 2 h du matin) ;
- des **RFC** avec plan de déploiement et de retour arrière ;
- des **comptes rendus d'incident** (postmortem) ;
- des **runbooks** (comme ceux du module 09).

Le lab de ce module t'entraîne à rédiger ces documents pour taskapi.

---

## Pour aller plus loin

- [Règlement DORA (EUR-Lex)](https://eur-lex.europa.eu/eli/reg/2022/2554/oj) et la page DORA de l'ACPR
- [ITIL 4 — vue d'ensemble (Axelos)](https://www.axelos.com/certifications/itil-service-management)
- [PCI DSS — documents officiels](https://www.pcisecuritystandards.org/)
