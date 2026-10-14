# Module 05 — Labs Ansible

> ⏱ ~3 h · Ton projet Ansible vit dans `infra/ansible/`. Les « serveurs » sont 3 conteneurs Ubuntu avec SSH (`05-ansible/lab/`).
> Libère de la RAM si besoin : `kind delete cluster --name bootcamp` (tu le recrées en 2 commandes : `make tf-cluster tf-platform`).

---

## Lab 5.1 — Le labo : 3 serveurs SSH (≈ 15 min)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/bootcamp_ansible -N "" -C "bootcamp-ansible"
cp ~/.ssh/bootcamp_ansible.pub 05-ansible/lab/authorized_keys
docker compose -f 05-ansible/lab/compose.yaml up -d --build
docker compose -f 05-ansible/lab/compose.yaml ps
ssh -i ~/.ssh/bootcamp_ansible -p 2221 -o StrictHostKeyChecking=no ansible@127.0.0.1 'hostname; sudo whoami'
```

Prépare le projet :

```bash
mkdir -p infra/ansible/{inventory/group_vars/all,playbooks,roles}
cd infra/ansible
openssl rand -hex 24 > .vault_pass && chmod 600 .vault_pass     # mot de passe du Vault (hors Git : .gitignore)
```

Écris `ansible.cfg` (inventaire, roles_path, utilisateur `ansible`, clé privée, `vault_password_file`, pipelining, `host_key_checking = False` pour le labo) et `inventory/hosts.yml` : groupe `lab` contenant `web` (web1:2221, web2:2222) et `db` (db1:2223), tous sur `127.0.0.1`.

```bash
ansible-inventory --graph
ansible all -m ping
ansible lab -m setup -a 'filter=ansible_distribution*'
ansible web -a 'uptime'
ansible db -b -m apt -a 'name=htop state=present update_cache=true'    # 1er run : changed
ansible db -b -m apt -a 'name=htop state=present'                      # 2e run : ok (idempotent)
```

---

## Lab 5.2 — Rôle `common` (≈ 40 min)

Variables dans `inventory/group_vars/all/main.yml` : `timezone`, `base_packages` (dont **acl**), `admin_users` (un compte `deploy`), `admin_public_key` (lookup de `~/.ssh/bootcamp_ansible.pub`).

Rôle `roles/common/` :
- paquets de base (`apt` avec `cache_valid_time`) ;
- fuseau horaire (lien `/etc/localtime` + `/etc/timezone`) ;
- comptes admin + clé autorisée (`ansible.posix.authorized_key`) ;
- `/etc/motd` depuis un template utilisant les **facts** ;
- durcissement SSH dans `/etc/ssh/sshd_config.d/99-hardening.conf` avec **`validate: /usr/sbin/sshd -t -f %s`** et un **handler** qui recharge sshd.

`playbooks/site.yml` avec un premier play `hosts: lab`, `become: true`, `roles: [common]`.

```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/site.yml --check --diff     # simulation
ansible-playbook playbooks/site.yml                    # vrai run
ansible-playbook playbooks/site.yml                    # 2e run : changed=0 attendu ✅
ssh -i ~/.ssh/bootcamp_ansible -p 2222 deploy@127.0.0.1    # le motd s'affiche
```

Teste la sécurité de `validate` : introduis volontairement une directive invalide dans le template (`PermitRootLogin peut-être`), relance : la tâche échoue, **le fichier n'est pas installé**, SSH fonctionne toujours. Corrige.

---

## Lab 5.3 — Vault et rôle `postgresql` (≈ 35 min)

```bash
printf 'vault_db_password: "%s"\n' "$(openssl rand -hex 16)" > inventory/group_vars/all/vault.yml
cat inventory/group_vars/all/vault.yml       # en clair… pour quelques secondes
ansible-vault encrypt inventory/group_vars/all/vault.yml
cat inventory/group_vars/all/vault.yml       # $ANSIBLE_VAULT;1.1;AES256…  → commitable
ansible-vault view inventory/group_vars/all/vault.yml
```

Dans `main.yml` : `db_name`, `db_user`, `db_password: "{{ vault_db_password }}"`, `db_host: db1`. Dans `group_vars/db.yml` : `pg_allowed_cidr: 172.30.0.0/24`.

Rôle `roles/postgresql/` :
- installer `postgresql` + `python3-psycopg2` ;
- trouver le dossier de config (`find` + `set_fact`) ;
- `lineinfile` pour `listen_addresses` et `max_connections` (boucle) ;
- template `pg_hba.conf.j2` ;
- service démarré, puis `meta: flush_handlers` ;
- `community.postgresql.postgresql_user` (avec `no_log`) et `postgresql_db`, en `become_user: postgres`.

```bash
ansible-playbook playbooks/site.yml --tags db
ansible db1 -b --become-user postgres -m community.postgresql.postgresql_query -a "db=taskapi query='select current_user'"
```

Expérience : retire `acl` de `base_packages`, recrée db1 (`docker compose -f ../../05-ansible/lab/compose.yaml up -d --force-recreate db1`), relance : lis bien l'erreur. Remets `acl`.

---

## Lab 5.4 — Rôles `taskapi` et `nginx` : déployer sans conteneur (≈ 40 min)

`group_vars/web.yml` : `app_env`, `taskapi_source_dir: "{{ playbook_dir }}/../../../app"`.

Rôle `roles/taskapi/` : utilisateur système, dossiers, copie du code et de `requirements.txt`, `pip` dans un venv, programme **supervisor** (template avec les variables d'environnement, mode `0640` car il contient le mot de passe), handlers avec `listen`.

Rôle `roles/nginx/` : installation, suppression du site par défaut, reverse proxy vers `127.0.0.1:8000` avec un en-tête `X-Served-By`, handlers « tester la config » puis « recharger » (même `listen`).

Ajoute à `site.yml` le play `hosts: web` avec les deux rôles et un `post_tasks` `uri` qui attend `/readyz` (retries/until).

```bash
ansible-playbook playbooks/site.yml
curl -si http://localhost:8081/version | grep -E 'X-Served-By|version'
curl -si http://localhost:8082/version | grep -E 'X-Served-By|version'
curl -s -X POST localhost:8081/api/tasks -H 'content-type: application/json' -d '{"title":"via ansible"}'
curl -s localhost:8082/api/tasks | jq      # même base derrière les deux serveurs
ansible-playbook playbooks/site.yml        # changed=0 ?
```

Si un run n'est pas idempotent, trouve quelle tâche est `changed` et corrige-la.

---

## Lab 5.5 — Déploiement progressif (≈ 20 min)

Écris `playbooks/rolling-update.yml` : `hosts: web`, **`serial: 1`**, `max_fail_percentage: 0`, `app_version` venant de `-e new_version=…`, rôle `taskapi`, `flush_handlers`, puis attente que `/version` renvoie la nouvelle version.

Dans un 2e terminal, surveille les deux serveurs :

```bash
while true; do for p in 8081 8082; do printf "%s:%s " $p "$(curl -s localhost:$p/version | jq -r .version)"; done; echo; sleep 1; done
```

```bash
ansible-playbook playbooks/rolling-update.yml -e new_version=1.1.0
```

Puis simule un échec sur web1 (casse volontairement le programme : `ansible web1 -b -m shell -a "chmod 000 /opt/taskapi/venv/bin/uvicorn"`) et relance avec `new_version=1.2.0` : web2 **ne doit pas** être touché. Répare avec `site.yml`.

---

## Lab 5.6 — Ton poste en Ansible + qualité (≈ 25 min)

Rôle `roles/devops_tools/` exécuté sur `localhost` (`connection: local`) : vérifie les versions des outils (`command` + `changed_when: false` + `assert`), installe `shellcheck`, `kubectx`, `tmux`, sécurise `~/.kube` (0700) et le kubeconfig (0600), ajoute des alias avec `blockinfile`.

```bash
ansible-playbook playbooks/workstation.yml -K
ansible-playbook playbooks/workstation.yml -K      # changed=0
grep -A8 "ALIAS GÉRÉS" ~/.bashrc
```

Compare avec `scripts/bootstrap-wsl.sh` : qu'est-ce qui est plus simple en bash ? plus robuste en Ansible ?

```bash
ansible-lint                      # corrige les avertissements (FQCN, noms, changed_when…)
cd -
```

---

## 🏁 Challenge (sans guide)

1. Ajoute un 3ᵉ groupe `lb` avec un 4ᵉ conteneur qui fait **load balancer nginx** devant web1/web2 (upstream généré depuis `groups['web']` et `hostvars`). Pendant un `rolling-update`, ajoute un `pre_task` qui retire l'hôte de l'upstream (`delegate_to` le LB) et un `post_task` qui le remet : **zéro erreur** côté client.
2. Ajoute un bloc `block/rescue/always` dans le rôle `taskapi` : si `/readyz` ne répond pas après le redémarrage, restaure le code précédent (sauvegarde via `copy … backup: true` ou dossier de release horodaté + lien symbolique `current`, comme Capistrano).
3. Installe Molecule (`pipx inject ansible-lint molecule molecule-plugins[docker]` ou `pipx install molecule`) et écris un scénario pour le rôle `nginx` qui vérifie l'idempotence.

---

## ✅ Validation

```bash
make check-05
```
