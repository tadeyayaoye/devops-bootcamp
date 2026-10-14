#!/usr/bin/env bash
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
A="$ROOT/infra/ansible"
cd "$A" 2>/dev/null || { echo "infra/ansible/ introuvable"; exit 1; }

title "Module 05 — Projet"
check "ansible.cfg présent" test -f ansible.cfg
check "Inventaire : 3 hôtes dans le groupe lab" bash -c '[[ $(ansible lab --list-hosts | tail -n +2 | wc -l) -eq 3 ]]'
for r in common postgresql taskapi nginx devops_tools; do
  check "Rôle $r présent" test -f roles/$r/tasks/main.yml
done
check "vault.yml chiffré" bash -c 'head -1 inventory/group_vars/all/vault.yml | grep -q ANSIBLE_VAULT'
check ".vault_pass non suivi par Git" bash -c '! git ls-files --error-unmatch .vault_pass'
check "Syntaxe de site.yml OK" ansible-playbook playbooks/site.yml --syntax-check
check "ansible-lint sans erreur" ansible-lint -q

title "Module 05 — Serveurs"
check "Les 3 serveurs répondent (ping)" ansible lab -m ping
check "Base taskapi créée sur db1" ansible db1 -b --become-user postgres -m community.postgresql.postgresql_query -a "db=taskapi query='select 1'"
check "web1 sert taskapi via nginx" http_ok http://localhost:8081/readyz
check "web2 sert taskapi via nginx" http_ok http://localhost:8082/readyz
check "Idempotence : 2e run de site.yml sans changement" bash -c '
  recap=$(ansible-playbook playbooks/site.yml 2>&1 | grep -E "^(web|db)[0-9]+ +:")
  [[ $(echo "$recap" | grep -c "changed=0.*failed=0") -eq 3 ]]'
hint "un run de site.yml doit afficher changed=0 sur tous les hôtes"

summary
