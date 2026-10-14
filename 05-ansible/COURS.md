# Module 05 — Gestion de configuration avec Ansible

> **Objectif** : comprendre le modèle d'Ansible (agentless, push, idempotence), structurer un projet professionnel (inventaire, group_vars, rôles, collections), protéger les secrets (Vault), et opérer des déploiements progressifs.
>
> **Durée** : cours ~1 h 30 · labs ~3 h · quiz 30 min

---

## 1. La gestion de configuration

Problème : 50 serveurs doivent avoir les mêmes paquets, utilisateurs, fichiers de config, services, réglages de sécurité… et **rester** conformes dans le temps.

| Outil | Modèle | Agent | Langage |
|---|---|---|---|
| **Ansible** | push (depuis un poste/CI) | **aucun** (SSH + Python sur la cible) | YAML |
| Puppet | pull (agent qui interroge un serveur) | oui | DSL Puppet |
| Chef | pull | oui | Ruby |
| SaltStack | push/pull | oui (minion) ou SSH | YAML |

Ansible a gagné la popularité par sa **simplicité** : rien à installer sur les cibles, du YAML lisible, une courbe d'apprentissage douce.

### Ansible dans un monde de conteneurs ?

Avec Kubernetes, on configure moins de serveurs à la main (images immuables). Mais Ansible reste très présent pour :
- configurer les **VM et serveurs physiques** (on-prem, bastions, bases de données, nœuds Kubernetes eux-mêmes : Kubespray est un ensemble de rôles Ansible) ;
- le **durcissement** (CIS benchmarks), les patchs de sécurité, les audits ;
- l'**automatisation réseau** (Cisco, Juniper…) et les **opérations** (redémarrages ordonnés, rotations de certificats, runbooks) ;
- l'orchestration de tâches dans les pipelines.

---

## 2. Architecture

```
          Nœud de contrôle (ton WSL / un runner CI / AWX)
          ┌──────────────────────────────────────────────┐
          │ ansible-playbook                             │
          │  ├─ inventaire (qui ?)                       │
          │  ├─ playbooks / rôles (quoi ?)               │
          │  ├─ variables, vault                         │
          │  └─ collections (modules, plugins)           │
          └───────────┬──────────────────────────────────┘
                      │ SSH (parallèle : forks)
        ┌─────────────┼─────────────────┐
        ▼             ▼                 ▼
     web1           web2              db1        ← python3 suffit
```

Pour chaque tâche et chaque hôte : Ansible **génère un petit programme Python** (le module + ses arguments), l'envoie par SSH, l'exécute, récupère un **JSON** (`changed`, `failed`, valeurs…), puis le supprime. Le *pipelining* évite de copier un fichier temporaire (plus rapide).

- **Facts** : au début du play, le module `setup` collecte des infos sur l'hôte (`ansible_facts['distribution']`, mémoire, IP…). Désactivable (`gather_facts: false`) pour gagner du temps.
- **Stratégie** `linear` (défaut) : chaque tâche s'exécute sur tous les hôtes avant de passer à la suivante ; `free` : chaque hôte avance à son rythme.
- **Forks** : nombre d'hôtes traités en parallèle (5 par défaut).

---

## 3. Inventaire

```yaml
all:
  children:
    web:
      hosts:
        web1: { ansible_host: 10.0.0.11 }
        web2: { ansible_host: 10.0.0.12 }
    db:
      hosts:
        db1: { ansible_host: 10.0.0.21, ansible_port: 2222 }
    prod:
      children: { web: {}, db: {} }
```

- Groupes, sous-groupes (`children`), un hôte peut appartenir à plusieurs groupes. Groupes implicites : `all`, `ungrouped`.
- Variables de connexion : `ansible_host`, `ansible_port`, `ansible_user`, `ansible_become`, `ansible_python_interpreter`, `ansible_connection` (`ssh`, `local`, `docker`, `winrm`…).
- **`group_vars/<groupe>.yml`** et **`host_vars/<hôte>.yml`** à côté de l'inventaire : la bonne place pour les variables (pas dans l'inventaire lui-même).
- **Inventaire dynamique** : un plugin interroge une source (AWS EC2, Azure, GCP, VMware, NetBox…) et construit groupes et hôtes à partir des tags. Indispensable en cloud.

```bash
ansible-inventory --graph
ansible-inventory --host web1          # toutes les variables résolues pour un hôte
```

---

## 4. Commandes ad hoc

```bash
ansible all -m ping                                  # connectivité + Python
ansible web -m setup -a 'filter=ansible_distribution*'
ansible db -b -m apt -a 'name=htop state=present'   # -b = become (sudo)
ansible all -a 'uptime'                              # module command par défaut
ansible web -m service -a 'name=nginx state=restarted' -b
```

Utile pour diagnostiquer ou agir ponctuellement. Pour tout ce qui doit être reproductible → un playbook.

---

## 5. Playbooks

```yaml
- name: Serveurs applicatifs          # un PLAY : des hôtes + des tâches
  hosts: web
  become: true                        # sudo
  vars:
    app_port: 8000
  pre_tasks: […]
  roles: [taskapi, nginx]
  tasks:
    - name: Installer nginx           # une TÂCHE = un appel de module, NOMMÉ
      ansible.builtin.apt:            # nom complet (FQCN) du module
        name: nginx
        state: present
      notify: Recharger nginx         # déclenche un handler SI changed
  post_tasks: […]
  handlers:
    - name: Recharger nginx
      ansible.builtin.service: { name: nginx, state: reloaded }
```

### Les mots-clés indispensables

| Mot-clé | Rôle |
|---|---|
| `become` / `become_user` | élévation de privilèges (sudo) / devenir un autre utilisateur (ex. `postgres` → nécessite le paquet `acl` sur la cible) |
| `register` | stocker le résultat d'une tâche |
| `when` | condition (`when: ansible_facts['os_family'] == 'Debian'`) |
| `loop` (+ `loop_control.label`) | itérer |
| `notify` / `handlers` / `listen` | actions déclenchées seulement si changement, exécutées **une fois** en fin de play (ou à `meta: flush_handlers`) |
| `block` / `rescue` / `always` | gestion d'erreurs façon try/catch/finally |
| `changed_when` / `failed_when` | redéfinir ce que signifie « changé » / « échoué » |
| `tags` | n'exécuter qu'une partie (`--tags db`, `--skip-tags common`) |
| `serial`, `max_fail_percentage` | déploiement progressif par lots |
| `delegate_to`, `run_once` | exécuter une tâche sur un autre hôte / une seule fois |
| `no_log: true` | masquer une tâche qui manipule des secrets |
| `check_mode`, `--diff` | simulation et affichage des différences |

### Idempotence : LE concept

Lancer un playbook 1 fois ou 10 fois doit donner le même résultat, et le 2ᵉ run doit afficher **`changed=0`**. Les modules sont conçus pour ça (`apt state=present` ne réinstalle pas, `template` ne réécrit que si le contenu diffère). Les pièges :

```yaml
# ❌ toujours "changed", et réexécuté à chaque run
- ansible.builtin.shell: curl -L https://… | tar xz -C /opt

# ✅ idempotent
- ansible.builtin.unarchive:
    src: https://…/outil.tar.gz
    dest: /opt
    remote_src: true
    creates: /opt/outil/bin/outil       # ne fait rien si le fichier existe
```

Règle : un module dédié > `command` > `shell`. Et si on doit utiliser `command`, toujours `creates`/`removes` ou `changed_when`.

---

## 6. Variables et templates

### Priorités (simplifiées, de la plus faible à la plus forte)

```
defaults/ d'un rôle   ← faites pour être surchargées
  < group_vars/all < group_vars/<groupe> < host_vars/<hôte>
  < facts de l'hôte
  < vars: du play < vars/ d'un rôle
  < set_fact / register
  < -e (extra vars)                       ← gagne toujours
```

Il y a 22 niveaux au total : retiens surtout que **`defaults` est le plus faible et `-e` le plus fort**, et mets tes valeurs dans `group_vars`.

### Jinja2

```jinja
{{ variable }}                       {{ liste | join(', ') }}
{{ valeur | default('x') }}          {{ mot_de_passe | password_hash('sha512') }}
{% for u in users %} … {% endfor %}  {% if env == 'prod' %} … {% endif %}
{{ ansible_managed }}                {{ hostvars['db1']['ansible_host'] }}
{{ groups['web'] }}                  {{ inventory_hostname }}
```

Le module `template` rend un fichier `.j2` sur la cible ; `validate:` permet de **tester le fichier avant de le mettre en place** (`nginx -t -c %s`, `sshd -t -f %s`, `visudo -cf %s`) → plus jamais de serveur verrouillé par une config cassée.

---

## 7. Rôles et collections

### Structure d'un rôle

```
roles/nginx/
├── defaults/main.yml     variables par défaut (surchargeables)
├── vars/main.yml         variables internes (priorité haute)
├── tasks/main.yml        les tâches
├── handlers/main.yml
├── templates/*.j2
├── files/                fichiers copiés tels quels
├── meta/main.yml         dépendances, plateformes, infos Galaxy
└── molecule/             tests (optionnel)
```

Un rôle = une responsabilité (`common`, `postgresql`, `nginx`, `taskapi`). Le playbook ne fait qu'**assembler** des rôles.

### Collections

Depuis Ansible 2.10, les modules sont distribués en **collections** (`namespace.collection`) : `ansible.builtin`, `ansible.posix`, `community.general`, `community.postgresql`, `amazon.aws`, `kubernetes.core`… On les installe via `ansible-galaxy collection install -r requirements.yml` et on écrit les noms complets (**FQCN**) des modules.

- `ansible-core` : le moteur + `ansible.builtin`.
- `ansible` (le paquet complet) : `ansible-core` + une sélection de collections.

---

## 8. Ansible Vault

Chiffre (AES-256) des fichiers ou des valeurs, pour pouvoir les commiter.

```bash
ansible-vault create group_vars/all/vault.yml
ansible-vault encrypt / decrypt / view / edit / rekey fichier
ansible-vault encrypt_string 's3cr3t' --name 'vault_db_password'
ansible-playbook site.yml --ask-vault-pass          # ou --vault-password-file .vault_pass
```

Bonnes pratiques :
- **Convention `vault_`** : `vault.yml` contient `vault_db_password`, et `main.yml` (en clair) contient `db_password: "{{ vault_db_password }}"` → on voit quelles variables existent sans déchiffrer.
- Le mot de passe du vault vient d'un fichier hors Git, d'une variable de CI, ou d'un script (gestionnaire de secrets). Plusieurs vaults : `--vault-id dev@… --vault-id prod@…`.
- `no_log: true` sur les tâches qui manipulent les secrets.
- Alternative en entreprise : lookup direct vers HashiCorp Vault / AWS Secrets Manager (`community.hashi_vault`).

---

## 9. Qualité et industrialisation

| Outil | Usage |
|---|---|
| `ansible-playbook --syntax-check` | syntaxe |
| `--check --diff` | simulation (dry run) |
| **ansible-lint** | bonnes pratiques (FQCN, noms de tâches, idempotence, `no-changed-when`…) |
| **Molecule** | tests de rôles : crée des conteneurs/VM, applique le rôle, vérifie l'idempotence (2ᵉ run `changed=0`), lance des vérifications |
| **AWX / Ansible Automation Platform** | interface web, RBAC, planification, journaux, inventaires et credentials centralisés |
| `ansible-pull` | mode pull (chaque machine récupère le repo et s'applique elle-même) |
| Execution Environments (`ansible-builder`) | image conteneur contenant ansible + collections + dépendances Python : reproductibilité en CI/AWX |

---

## 10. Ansible et les autres outils

- **Terraform** crée la VM → sort son IP → **Ansible** la configure (inventaire dynamique ou généré).
- **Packer + Ansible** : construire une image de VM « dorée » préconfigurée (immuable) plutôt que configurer au démarrage.
- **cloud-init** : configuration minimale au premier démarrage d'une VM cloud.
- **Kubernetes** : Ansible peut piloter des ressources (`kubernetes.core.k8s`, `helm`), mais pour les applis on préfère GitOps.

---

## Pièges classiques

- `shell`/`command` sans `changed_when` → rapports faux, idempotence perdue.
- Variables dans le playbook au lieu de `group_vars` → doublons et surprises de priorité.
- `become_user: postgres` qui échoue (« Failed to set permissions on the temporary files… ») → installer `acl` sur la cible.
- Handlers qui ne s'exécutent pas car le play a échoué avant la fin (`--force-handlers`, ou `meta: flush_handlers` au bon endroit).
- Secrets en clair dans les logs → `no_log`.
- Modifier sshd sans `validate` → plus d'accès au serveur.
- `apt update_cache: true` sans `cache_valid_time` → lent et toujours `changed`.

---

## Pour aller plus loin

- [Ansible documentation — Getting started](https://docs.ansible.com/ansible/latest/getting_started/index.html)
- [Ansible Lint](https://ansible.readthedocs.io/projects/lint/) · [Molecule](https://ansible.readthedocs.io/projects/molecule/)
- [Geerling Guy — rôles de référence](https://github.com/geerlingguy?tab=repositories&q=ansible-role) et le livre « Ansible for DevOps »
