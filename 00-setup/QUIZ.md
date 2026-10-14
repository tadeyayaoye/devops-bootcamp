# Module 00 — Quiz

Réponds **à voix haute** avant de déplier. Si tu hésites, c'est une zone floue : note-la dans PROGRESSION.md.

<details><summary>1. Pourquoi ne faut-il pas travailler dans <code>/mnt/c</code> sous WSL2 ?</summary>

Parce que `/mnt/c` est le disque Windows exposé à la VM Linux via le protocole réseau 9P : les accès fichiers sont beaucoup plus lents (catastrophique pour `git status`, `pip install`, les builds Docker), les permissions Unix sont émulées (bit exécutable, `chmod`), et les outils Windows peuvent introduire des CRLF. Le système de fichiers natif de la distro (ext4 dans un VHDX) est rapide et fidèle à un vrai Linux.
</details>

<details><summary>2. Quelle est la différence entre SIGTERM et SIGKILL ? Lequel envoie <code>docker stop</code> ?</summary>

SIGTERM (15) demande poliment l'arrêt : le process peut l'intercepter pour finir ses requêtes, fermer ses connexions, vider ses buffers. SIGKILL (9) est exécuté par le noyau : impossible à intercepter, mort immédiate. `docker stop` envoie SIGTERM, attend 10 s (configurable `-t`), puis SIGKILL. Kubernetes fait pareil avec `terminationGracePeriodSeconds` (30 s par défaut), après avoir exécuté un éventuel hook `preStop`.
</details>

<details><summary>3. Pourquoi dit-on qu'être membre du groupe <code>docker</code> équivaut à être root ?</summary>

Le démon Docker tourne en root et quiconque peut parler à son socket peut lancer `docker run -v /:/host --privileged ...` : il obtient alors un accès root complet au système de fichiers de l'hôte. C'est pour ça qu'on évite d'exposer le socket Docker (dans Jenkins par exemple, on le fait en labo mais c'est un risque à savoir expliquer), et que des alternatives rootless existent (Podman, Docker rootless, BuildKit rootless, Kaniko).
</details>

<details><summary>4. Que fait <code>set -euo pipefail</code> ?</summary>

`-e` : le script s'arrête à la première commande qui échoue. `-u` : utiliser une variable non définie est une erreur (évite `rm -rf "$DIR/"` avec DIR vide…). `-o pipefail` : le code retour d'un pipe est celui de la dernière commande en échec, pas seulement de la dernière commande (sinon `curl ... | jq` masque l'échec du curl).
</details>

<details><summary>5. Qu'est-ce qu'une branche Git, techniquement ?</summary>

Un simple pointeur mobile vers un commit : un fichier `.git/refs/heads/<nom>` contenant un hash. Créer une branche est instantané et ne copie rien. `HEAD` est un pointeur vers la branche courante (ou directement vers un commit en « detached HEAD »).
</details>

<details><summary>6. Merge ou rebase : lequel choisir, et quelle est la règle à ne pas enfreindre ?</summary>

Merge préserve l'historique réel (commit de merge, utile pour tracer l'intégration d'une feature), rebase produit un historique linéaire plus lisible en rejouant les commits au-dessus de la cible. Règle d'or : ne jamais rebaser (réécrire) des commits déjà partagés/poussés sur une branche où d'autres travaillent. Si on doit le faire sur sa propre branche de PR : `git push --force-with-lease`.
</details>

<details><summary>7. Un collègue a poussé sur main un commit qui casse la prod. Tu fais quoi : <code>reset</code> ou <code>revert</code> ?</summary>

`git revert <sha>` : il crée un nouveau commit qui annule les changements, sans réécrire l'historique partagé. `reset` + force-push sur main casserait les clones de toute l'équipe (et est normalement interdit par la protection de branche). En GitOps, le revert est d'ailleurs LA méthode de rollback.
</details>

<details><summary>8. Tu as fait <code>git reset --hard</code> et perdu 3 commits non poussés. Comment les récupérer ?</summary>

`git reflog` liste tous les déplacements de HEAD avec leurs hash. On repère l'état d'avant (`HEAD@{1}` par ex.) et on fait `git reset --hard HEAD@{1}` ou `git branch sauvetage <sha>`. Les objets non référencés restent ~90 jours (jusqu'au `git gc`).
</details>

<details><summary>9. Différence entre <code>/healthz</code> et <code>/readyz</code> dans taskapi ? Pourquoi ne pas tester la base dans la liveness ?</summary>

Liveness = « le process est-il vivant/non bloqué ? » ; un échec entraîne un redémarrage du conteneur. Readiness = « puis-je recevoir du trafic ? » ; un échec retire le pod des endpoints du Service sans le redémarrer. Si la liveness testait la base, une panne Postgres ferait redémarrer en boucle tous les pods de l'API, ce qui n'arrange rien et ajoute du bruit (et peut empirer la situation au retour de la base : thundering herd).
</details>

<details><summary>10. Pourquoi deux repos (code et GitOps) plutôt qu'un seul ?</summary>

Séparer « ce qu'on construit » de « ce qui est déployé » : droits différents (les devs n'ont pas forcément le droit de modifier la prod), historique de déploiement propre et auditable (chaque commit du repo GitOps = un changement d'état du cluster), pas de boucle infinie (la CI qui commite le nouveau tag ne redéclenche pas la CI applicative), et possibilité de déployer plusieurs applis/environnements depuis un seul repo de config.
</details>

<details><summary>11. Qu'est-ce que l'approche 12-factor apporte pour la configuration ?</summary>

La configuration (URLs, identifiants, flags) est lue dans l'environnement, pas dans le code ni dans l'image. Une même image immuable est donc promue de dev à prod ; seuls les variables/secrets changent. C'est ce que fait `config.py` avec pydantic-settings.
</details>

<details><summary>12. Que se passe-t-il si tu commites un token GitHub puis le supprimes dans le commit suivant ?</summary>

Il reste dans l'historique Git (et dans tous les clones, forks, caches). Il faut le considérer comme compromis : le révoquer immédiatement, en générer un nouveau, puis éventuellement nettoyer l'historique (`git filter-repo`) — mais la révocation est la seule vraie mesure. GitHub push protection et gitleaks (module 07) servent à l'empêcher en amont.
</details>
