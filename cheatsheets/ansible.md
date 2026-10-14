# Ansible — fiche mémo

```bash
ansible-inventory --graph / --host web1            ansible all -m ping
ansible web -b -m apt -a 'name=htop state=present' ansible all -a 'uptime'
ansible web1 -m setup -a 'filter=ansible_distribution*'
ansible-playbook site.yml [--check] [--diff] [-l web1] [--tags db] [--skip-tags x] [-e k=v] [-K] [-v…]
ansible-playbook site.yml --syntax-check | --list-tasks | --list-hosts | --start-at-task "…" | --step
ansible-vault create / edit / view / encrypt / decrypt / rekey f.yml
ansible-vault encrypt_string 's3cr3t' --name vault_x
ansible-galaxy collection install -r requirements.yml   ansible-galaxy role init roles/x
ansible-lint                                            ansible-doc ansible.builtin.template
```

```yaml
- name: Serveurs web
  hosts: web
  become: true
  serial: 1                       # rolling
  max_fail_percentage: 0
  vars: { port: 8000 }
  pre_tasks: [ … ]
  roles: [common, nginx]
  tasks:
    - name: Template avec validation
      ansible.builtin.template: { src: x.j2, dest: /etc/x.conf, mode: "0644", validate: "x -t %s" }
      notify: Recharger x
    - name: Commande idempotente
      ansible.builtin.command: /opt/install.sh
      args: { creates: /opt/app/bin/app }
    - name: Lecture seule
      ansible.builtin.command: app --version
      register: v
      changed_when: false
    - name: Boucle
      ansible.builtin.user: { name: "{{ item }}" }
      loop: "{{ users }}"
      when: ansible_facts['os_family'] == "Debian"
    - block: [ … ]
      rescue: [ … ]
      always: [ … ]
  handlers:
    - name: Recharger x
      ansible.builtin.service: { name: x, state: reloaded }
      listen: Recharger x
```

Rôle : `defaults/` (faible priorité) · `vars/` · `tasks/` · `handlers/` · `templates/` · `files/` · `meta/`.
Priorités : defaults < group_vars/all < group_vars/groupe < host_vars < vars du play < set_fact < **-e**.
Pièges : `acl` pour `become_user`, `cache_valid_time` sur apt, `no_log` pour les secrets, `flush_handlers`.
