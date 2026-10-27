# Module 13 — Quiz contexte bancaire

<details><summary>1. Qu'est-ce qu'une RFC et que doit-elle contenir au minimum ?</summary>

Une *Request For Change* : la demande formelle de modification de la production. Au minimum : description et justification, périmètre et impacts, analyse de risque, plan de déploiement, plan de tests, **plan de retour arrière**, fenêtre d'intervention, responsables et communication.
</details>

<details><summary>2. Changement standard, normal, urgent : quelle différence ?</summary>

Standard : pré-autorisé car répétitif, maîtrisé et à faible risque (souvent un déploiement par une chaîne automatisée validée) ; pas de passage en CAB à chaque fois. Normal : évalué et approuvé en CAB. Urgent : nécessaire pour résoudre un incident, circuit d'approbation accéléré (ECAB), régularisé ensuite.
</details>

<details><summary>3. Comment le DevOps peut-il cohabiter avec la séparation des tâches exigée par les audits ?</summary>

En déplaçant le contrôle dans l'outillage : le développeur propose (PR, demande de release), une autre personne approuve (revue, gate XL Release, CAB), et c'est un outil automatisé et journalisé qui déploie (pipeline, Argo CD, XL Release). Aucun humain n'agit directement en production ; tout est tracé et réversible. C'est souvent plus conforme qu'un déploiement manuel.
</details>

<details><summary>4. Qu'est-ce que le règlement DORA et qu'implique-t-il pour une équipe DevOps ?</summary>

Le *Digital Operational Resilience Act* (UE 2022/2554), applicable depuis le 17 janvier 2025 aux entités financières : gestion des risques TIC, classification et déclaration des incidents majeurs au régulateur, tests de résilience, maîtrise des prestataires TIC tiers. Pour un DevOps : traçabilité des changements, supervision et gestion d'incident efficaces, plans de continuité testés, gestion des vulnérabilités, maîtrise des dépendances (cloud, SaaS).
</details>

<details><summary>5. RTO et RPO ?</summary>

RTO (*Recovery Time Objective*) : durée maximale acceptable d'interruption avant le rétablissement du service. RPO (*Recovery Point Objective*) : quantité maximale de données qu'on accepte de perdre, exprimée en temps (dernier point de sauvegarde/réplication). Ils dimensionnent le PCA/PRA (réplication synchrone, sauvegardes fréquentes, site de secours…).
</details>

<details><summary>6. Pourquoi la nuit est-elle si importante dans une banque ?</summary>

C'est la fenêtre batch : traitements de fin de journée (arrêté comptable, calcul des soldes et intérêts, échanges de fichiers interbancaires, reporting réglementaire, alimentation des entrepôts de données, sauvegardes). Ils doivent se terminer avant l'ouverture des services du matin : un retard de batch est un incident visible par les clients et les agences.
</details>

<details><summary>7. Quels sont les principaux ordonnanceurs du marché ?</summary>

Control-M (BMC), Dollar Universe/$U (Broadcom), VTOM (Absyss), Autosys (Broadcom), IBM Workload Scheduler (ex-TWS), et en open source Apache Airflow, JS7 JobScheduler, Rundeck. Control-M est le plus répandu dans les grandes banques et la cible de nombreuses migrations.
</details>

<details><summary>8. Qu'est-ce qu'un CAB et un gel des changements ?</summary>

Le *Change Advisory Board* est l'instance (souvent hebdomadaire) qui évalue et approuve les changements normaux. Un gel (freeze) est une période où les changements sont interdits ou très restreints : fin d'année, arrêtés comptables, opérations exceptionnelles, événements commerciaux.
</details>

<details><summary>9. Pourquoi ne peut-on pas utiliser des données de production en recette ?</summary>

RGPD, secret bancaire et PCI DSS : les données personnelles et de cartes doivent être protégées et limitées à l'usage nécessaire. Les environnements hors production sont moins sécurisés. On utilise des jeux de données synthétiques ou des données anonymisées/pseudonymisées de manière irréversible.
</details>

<details><summary>10. Que contient un dossier d'exploitation (DEX) ?</summary>

L'architecture et les flux, les composants et versions, les procédures d'exploitation (démarrage, arrêt, contrôles de santé), sauvegardes/restaurations, supervision et alertes, consignes d'incident et d'escalade, chaînes batch et consignes de pilotage, objectifs de continuité (RTO/RPO), contacts.
</details>
