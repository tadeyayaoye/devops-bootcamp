# Module 07 — Quiz qualité, DevSecOps, GitHub Actions

<details><summary>1. Qu'est-ce qu'une quality gate et pourquoi la faire porter sur le « nouveau code » ?</summary>

Un ensemble de conditions bloquantes sur des métriques (couverture, bugs, vulnérabilités, duplications, hotspots revus) évaluées à chaque analyse ; si elle échoue, le pipeline échoue. Sur le nouveau code (Clean as You Code) : on n'exige pas de corriger toute la dette historique d'un coup (gate toujours rouge = gate ignorée), mais on garantit que chaque changement est propre ; la qualité globale s'améliore mécaniquement avec le temps.
</details>

<details><summary>2. Comment Jenkins sait-il que la quality gate est OK, alors que l'analyse est asynchrone ?</summary>

Le scanner envoie le rapport et écrit un `report-task.txt` (ID de la tâche). Le serveur traite l'analyse en arrière-plan (Compute Engine), puis appelle le webhook Jenkins `/sonarqube-webhook/`. L'étape `waitForQualityGate` attend ce callback (ou interroge l'API) et échoue si le statut est ERROR. Sans webhook configuré, l'étape attend jusqu'au timeout.
</details>

<details><summary>3. SAST, SCA, DAST : différences ?</summary>

SAST : analyse statique de ton code source (SonarQube, Semgrep, CodeQL). SCA : analyse des composants tiers (dépendances, paquets de l'image) contre les bases de CVE (Trivy, Grype, Dependabot). DAST : tests dynamiques d'une application en fonctionnement, de l'extérieur (OWASP ZAP). On ajoute la détection de secrets et l'analyse d'IaC/config.
</details>

<details><summary>4. Ton scan Trivy remonte 120 CVE, dont 40 HIGH. Que fais-tu ?</summary>

Trier : sévérité et surtout exploitabilité (EPSS, présence dans KEV), existence d'un correctif, composant réellement utilisé/exposé. Corriger vite ce qui est corrigeable (mise à jour de l'image de base souvent suffisante, versions de dépendances). Bloquer en CI sur un seuil réaliste (CRITICAL corrigeables), tracer le reste en tickets, documenter les exceptions avec justification et date d'expiration (`.trivyignore`). Réduire la surface (image slim/distroless).
</details>

<details><summary>5. Qu'est-ce qu'un SBOM et à quoi sert-il en cas de nouvelle CVE critique ?</summary>

Un inventaire structuré (SPDX, CycloneDX) de tous les composants et versions d'un artefact. Lorsqu'une CVE critique est publiée (type Log4Shell), on interroge les SBOM stockés pour savoir immédiatement quelles images/applications sont concernées, au lieu de rescanner tout le parc. Il sert aussi à la conformité (licences, réglementations).
</details>

<details><summary>6. Pourquoi épingler une action GitHub par SHA plutôt que par tag ?</summary>

Un tag Git est mobile : un attaquant qui compromet le compte du mainteneur peut le réécrire vers du code malveillant, exécuté ensuite avec les secrets de tous les workflows qui l'utilisent (tj-actions/changed-files en 2025, trivy-action et setup-trivy en mars 2026). Un SHA de commit est immuable. On ajoute le tag en commentaire pour la lisibilité et on laisse Dependabot/Renovate proposer les mises à jour.
</details>

<details><summary>7. Que retenir de la compromission de Trivy en mars 2026 ?</summary>

Les outils de sécurité sont eux-mêmes des dépendances à risque, souvent exécutés avec beaucoup de privilèges (secrets CI, socket Docker). Bonnes pratiques : épingler les versions/digests et les actions par SHA, vérifier les signatures/checksums, limiter les permissions et secrets accessibles aux jobs, surveiller les avis de sécurité, et pouvoir faire une rotation rapide des secrets. Les utilisateurs touchés devaient considérer tous les secrets accessibles au pipeline comme compromis.
</details>

<details><summary>8. GITHUB_TOKEN, PAT, OIDC : lequel choisir ?</summary>

`GITHUB_TOKEN` : jeton éphémère généré pour chaque run, limité au repo, permissions réglables — à préférer pour tout ce qui touche GitHub (GHCR, PR, commentaires). PAT : jeton personnel longue durée, à éviter (fuite = accès durable) sauf cas non couverts. OIDC : le workflow obtient un jeton d'identité signé qu'un cloud (AWS, GCP, Azure, Vault) échange contre des identifiants temporaires — plus aucun secret stocké.
</details>

<details><summary>9. Pourquoi la couverture remonte-t-elle à 0 % dans SonarQube alors que les tests la calculent ?</summary>

SonarQube ne calcule pas la couverture : il importe le rapport (coverage.xml). Causes : rapport non généré avant l'analyse, mauvais chemin dans `sonar.python.coverage.reportPaths`, ou chemins de fichiers dans le rapport qui ne correspondent pas aux sources vues par le scanner (tests exécutés dans un autre dossier/conteneur que l'analyse).
</details>

<details><summary>10. Comment signer une image et vérifier la signature au déploiement ?</summary>

Avec cosign (Sigstore) : `cosign sign` sur le digest de l'image, soit avec une clé (KMS), soit en keyless (identité OIDC de la CI, certificat éphémère Fulcio, enregistrement dans le journal Rekor). Vérification : `cosign verify` avec l'identité attendue (workflow, repo) et l'émetteur OIDC. Côté cluster, une politique d'admission (Kyverno verifyImages, Sigstore policy-controller) refuse les images non signées par l'identité attendue.
</details>

<details><summary>11. Pourquoi les runners GitHub ne peuvent-ils pas déployer sur ton cluster kind, et quelle est la solution ?</summary>

Les runners hébergés sont sur Internet ; le cluster est sur ton poste derrière NAT, sans API exposée. Solutions : runner self-hosted dans ton réseau (risqué sur un repo public), exposer l'API (à éviter), ou modèle pull (GitOps) : la CI publie l'image et met à jour le repo de configuration, et Argo CD dans le cluster tire les changements. Le modèle pull évite aussi de donner des identifiants du cluster à la CI.
</details>

<details><summary>12. Qu'est-ce que SLSA ?</summary>

Supply-chain Levels for Software Artifacts : un cadre (OpenSSF) qui définit des niveaux de garantie sur la chaîne de build : provenance générée automatiquement, build sur une plateforme hébergée et durcie, provenance signée et non falsifiable, builds isolés/reproductibles. Il permet de vérifier qu'un artefact a bien été produit à partir d'un source donné par un processus attendu.
</details>
