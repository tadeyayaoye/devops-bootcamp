# Module 05 — Quiz Ansible

<details><summary>1. Que veut dire « agentless » et quelles sont les conséquences ?</summary>

Aucun démon à installer sur les cibles : Ansible se connecte en SSH (WinRM pour Windows), pousse un module Python temporaire, l'exécute et récupère un JSON. Avantages : rien à maintenir sur les serveurs, adoption immédiate. Contreparties : il faut SSH + Python sur la cible, pas de convergence continue (rien ne se passe entre deux runs, sauf à planifier via CI/AWX ou ansible-pull), performances limitées sur des milliers de nœuds (forks, pipelining, mitogen).
</details>

<details><summary>2. Qu'est-ce que l'idempotence et comment la vérifier ?</summary>

Appliquer plusieurs fois le même playbook donne le même état, sans effet de bord supplémentaire. Vérification : un 2e run doit afficher `changed=0` partout (Molecule le teste automatiquement). On l'obtient avec des modules déclaratifs (`apt`, `template`, `user`…) et en encadrant `command`/`shell` avec `creates`, `removes`, `changed_when`.
</details>

<details><summary>3. Qu'est-ce qu'un handler et quand s'exécute-t-il ?</summary>

Une tâche déclenchée par `notify` uniquement si la tâche notifiante a produit un changement. Il s'exécute une seule fois, à la fin du play (même s'il a été notifié plusieurs fois), ou au moment d'un `meta: flush_handlers`. `listen` permet d'abonner plusieurs handlers à un même nom. Si le play échoue avant la fin, les handlers ne tournent pas (sauf `--force-handlers`).
</details>

<details><summary>4. Où mettre les variables et quelle est la priorité ?</summary>

Valeurs par défaut des rôles dans `defaults/` (priorité la plus faible), valeurs d'environnement dans `group_vars/` et `host_vars/` de l'inventaire, valeurs internes d'un rôle dans `vars/`. `-e` (extra vars) gagne toujours. Il y a 22 niveaux ; l'important est d'avoir une convention d'équipe et d'éviter de définir la même variable à plusieurs endroits.
</details>

<details><summary>5. Comment gérer les secrets avec Ansible ?</summary>

Ansible Vault (chiffrement AES-256 de fichiers ou de valeurs, commitables), avec la convention `vault_*` référencées depuis des fichiers en clair, mot de passe fourni via fichier hors Git / variable de CI / script. `no_log: true` sur les tâches sensibles. En entreprise, souvent un lookup vers un vrai gestionnaire de secrets (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault).
</details>

<details><summary>6. Pourquoi <code>become_user: postgres</code> échoue-t-il parfois avec une erreur de permissions sur des fichiers temporaires ?</summary>

Ansible copie le module dans un fichier temporaire appartenant à l'utilisateur de connexion, puis doit le rendre lisible par l'utilisateur cible non privilégié. Il utilise pour cela les ACL POSIX (`setfacl`) : sans le paquet `acl` sur la cible, c'est impossible. Solutions : installer `acl`, ou utiliser le pipelining (pas de fichier temporaire dans certains cas).
</details>

<details><summary>7. <code>command</code>, <code>shell</code> ou un module dédié ?</summary>

Toujours le module dédié s'il existe (idempotent, check mode, diff, gestion d'erreurs). Sinon `command` (pas de shell : plus sûr, pas d'injection, pas de pipes/redirections), et `shell` seulement si on a besoin de fonctionnalités du shell. Dans les deux cas : `changed_when`/`creates`/`removes`, et éviter les variables non quotées.
</details>

<details><summary>8. Comment faire un déploiement sans interruption sur une ferme de serveurs ?</summary>

`serial` (1 hôte ou un pourcentage à la fois), `max_fail_percentage: 0` pour stopper au premier échec, retrait de l'hôte du load balancer en `pre_tasks` (`delegate_to` le LB ou appel d'API), mise à jour, vérification de santé (`uri` + `until`), remise dans le pool en `post_tasks`. `block/rescue` pour un rollback automatique.
</details>

<details><summary>9. À quoi sert <code>validate</code> sur les modules template/copy/lineinfile ?</summary>

Tester le fichier généré avant de remplacer l'original (`nginx -t -c %s`, `sshd -t -f %s`, `visudo -cf %s`). Si la validation échoue, le fichier n'est pas installé et la tâche échoue : on évite de casser un service, ou de se verrouiller hors d'un serveur avec une config SSH invalide.
</details>

<details><summary>10. Inventaire statique ou dynamique ?</summary>

Statique : fichier INI/YAML, adapté à un parc stable. Dynamique : un plugin interroge une source de vérité (API cloud, VMware, NetBox, CMDB) à chaque exécution et construit les groupes à partir des tags/métadonnées. Indispensable dès que les machines sont créées/détruites automatiquement (autoscaling, Terraform).
</details>

<details><summary>11. Différence entre un rôle et une collection ?</summary>

Un rôle est une unité réutilisable de configuration (tasks, handlers, templates, defaults…) avec une responsabilité. Une collection est un format de distribution qui peut contenir des modules, plugins, rôles et playbooks, sous un espace de noms (`community.postgresql`). On référence les modules par leur FQCN (`ansible.builtin.copy`).
</details>

<details><summary>12. Comment tester un rôle Ansible ?</summary>

`ansible-lint` (statique), `--syntax-check`, `--check --diff` (simulation), et Molecule : il crée des instances éphémères (conteneurs, VM), applique le rôle (converge), le réapplique pour vérifier l'idempotence, exécute des vérifications (verify, avec Ansible ou Testinfra), puis détruit tout. Intégré en CI sur chaque PR du rôle.
</details>

<details><summary>13. Ansible ou image immuable (Packer, conteneurs) ?</summary>

Configurer des serveurs vivants (mutable) entraîne de la dérive dans le temps (« snowflake servers »). L'approche immuable construit une image complète (Packer + Ansible, ou Docker) puis remplace les instances au lieu de les modifier. En pratique on combine : Ansible pour construire les images ou gérer ce qui reste mutable (bases, réseau, legacy), et des images/conteneurs immuables pour les applis.
</details>

<details><summary>14. Que fait <code>--check --diff</code> et quelles sont ses limites ?</summary>

Simule le run (les modules compatibles prédisent s'ils changeraient quelque chose) et affiche les différences de fichiers. Limites : les tâches `command`/`shell` sont ignorées (sauf `check_mode: false`), et les tâches qui dépendent du résultat d'une tâche précédente non exécutée peuvent échouer ou donner un résultat incomplet.
</details>
