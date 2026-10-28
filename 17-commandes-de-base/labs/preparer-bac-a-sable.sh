#!/usr/bin/env bash
# Crée un bac à sable d'exercices dans ~/bac-a-sable (Linux / WSL). Relançable : il repart de zéro.
#   bash 17-commandes-de-base/labs/preparer-bac-a-sable.sh
set -euo pipefail

B="${1:-$HOME/bac-a-sable}"
rm -rf "$B"
mkdir -p "$B"/{logs,data,scripts,config,docs/projets/{alpha,beta,gamma},archives,tmp}
cd "$B"

# Un journal applicatif de 500 lignes (niveaux variés)
niveaux=(INFO INFO INFO INFO WARN ERROR DEBUG)
for i in $(seq 1 500); do
  n=${niveaux[$((RANDOM % ${#niveaux[@]}))]}
  printf '2026-10-28 %02d:%02d:%02d %-5s [worker-%d] traitement de la requete %d\n' \
    $((i / 60 % 24)) $((i % 60)) $((RANDOM % 60)) "$n" $((RANDOM % 4)) "$i"
done > logs/app.log
echo "2026-10-28 23:59:59 ERROR [worker-1] connexion refusee a la base : password=NE_JAMAIS_LOGUER_UN_MOT_DE_PASSE" >> logs/app.log

# Un journal d'accès HTTP
for i in $(seq 1 200); do
  codes=(200 200 200 200 201 404 500)
  printf '192.168.1.%d - - [28/Oct/2026:10:%02d:00] "GET /api/tasks/%d HTTP/1.1" %s %d\n' \
    $((RANDOM % 20 + 1)) $((i % 60)) $((RANDOM % 50)) "${codes[$((RANDOM % 7))]}" $((RANDOM % 5000))
done > logs/access.log

# Un CSV de clients
{
  echo "id;nom;ville;solde"
  villes=(Paris Lyon Lille Nantes Marseille Bordeaux)
  for i in $(seq 1 30); do
    echo "$i;client$i;${villes[$((RANDOM % 6))]};$(( (RANDOM % 20000) - 5000 ))"
  done
} > data/clients.csv

# Configuration et secret (droits à corriger dans les exercices)
cat > config/app.conf <<'EOF'
# configuration de demo
port=8000
log_level=INFO
db_host=localhost
db_user=taskapi
EOF
echo "jeton-secret-de-demo" > config/secret.txt
chmod 666 config/secret.txt          # volontairement TROP ouvert

# Un script NON exécutable (exercice chmod) et une boucle infinie (exercice kill)
cat > scripts/bonjour.sh <<'EOF'
#!/usr/bin/env bash
echo "Bonjour $(whoami), il est $(date +%H:%M)"
EOF
chmod 644 scripts/bonjour.sh
cat > scripts/boucle.sh <<'EOF'
#!/usr/bin/env bash
# Tourne sans fin et ignore Ctrl+C ET SIGTERM : il faudra forcer (SIGKILL)
trap 'echo "SIGTERM recu... et ignore !"' TERM
trap 'echo "SIGINT recu... et ignore !"' INT
while true; do echo "boucle $$ toujours en vie $(date +%T)"; sleep 5; done
EOF
cat > scripts/poli.sh <<'EOF'
#!/usr/bin/env bash
# Tourne sans fin mais s'arrete proprement sur SIGTERM
trap 'echo "SIGTERM recu : je ferme proprement"; exit 0' TERM
while true; do sleep 2; done
EOF
chmod 755 scripts/boucle.sh scripts/poli.sh

# Des documents de tailles et dates variées
for p in alpha beta gamma; do
  for j in 1 2 3; do echo "Projet $p - document $j" > "docs/projets/$p/doc$j.txt"; done
done
head -c 30M /dev/urandom > docs/projets/beta/gros-fichier.bin
touch -d "2025-01-15" docs/projets/alpha/doc1.txt docs/projets/alpha/doc2.txt
touch docs/.fichier-cache

echo "✔ bac à sable prêt dans $B"
ls -la "$B"
