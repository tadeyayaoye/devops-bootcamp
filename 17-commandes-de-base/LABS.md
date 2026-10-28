# Module 17 — Labs : 50 exercices Linux + PowerShell

> ⏱ ~2 h · Fais chaque exercice **deux fois** : dans Ubuntu (WSL), puis dans PowerShell (Windows). Cherche d'abord seul·e (`man`, `--help`, `Get-Help -Examples`, le [cours](COURS.md)), puis déplie la réponse.

---

## Préparer les bacs à sable (≈ 5 min)

**Linux (Ubuntu)** :

```bash
cd ~/devops-bootcamp && git pull
bash 17-commandes-de-base/labs/preparer-bac-a-sable.sh
cd ~/bac-a-sable
```

**PowerShell (Windows)** : le repo est dans Ubuntu, accessible depuis Windows par `\\wsl.localhost\`. Remplace `tayaya` par ton utilisateur Linux si besoin :

```powershell
powershell -ExecutionPolicy Bypass -File "\\wsl.localhost\Ubuntu-24.04\home\tayaya\devops-bootcamp\17-commandes-de-base\labs\preparer-bac-a-sable.ps1"
cd $HOME\bac-a-sable
```

Les deux scripts créent la même arborescence : `logs/app.log` (500 lignes), `logs/access.log`, `data/clients.csv`, `config/`, `scripts/`, `docs/projets/{alpha,beta,gamma}` (dont un fichier de 30 Mo et un fichier caché).

---

## A. Se repérer (5 exercices)

<details><summary>A1. Affiche le dossier courant, puis va dans <code>logs</code> et reviens au dossier précédent.</summary>

```bash
pwd ; cd logs ; cd -
```
```powershell
Get-Location ; Set-Location logs ; Set-Location ..        # (PowerShell 7 : cd - fonctionne aussi)
```
</details>

<details><summary>A2. Liste le contenu de <code>docs</code> en détail, fichiers cachés compris.</summary>

```bash
ls -la docs
```
```powershell
Get-ChildItem docs -Force
```
</details>

<details><summary>A3. Affiche toute l'arborescence du bac à sable.</summary>

```bash
tree ~/bac-a-sable           # ou : find ~/bac-a-sable
```
```powershell
tree /F $HOME\bac-a-sable    # ou : Get-ChildItem -Recurse -Name
```
</details>

<details><summary>A4. Trouve l'emplacement de la commande <code>python3</code> (Linux) / <code>powershell</code> (Windows).</summary>

```bash
which python3 ; type python3
```
```powershell
Get-Command powershell | Select-Object Source
```
</details>

<details><summary>A5. Affiche les exemples d'aide de la commande qui lit un fichier.</summary>

```bash
man tail          # (q pour quitter)  ou : tail --help
```
```powershell
Get-Help Get-Content -Examples     # la 1re fois : Update-Help (en administrateur)
```
</details>

---

## B. Lire des fichiers (8 exercices)

<details><summary>B1. Affiche les 20 premières lignes de <code>logs/app.log</code>.</summary>

```bash
head -n 20 logs/app.log
```
```powershell
Get-Content logs\app.log -TotalCount 20
```
</details>

<details><summary>B2. Affiche les 20 dernières lignes.</summary>

```bash
tail -n 20 logs/app.log
```
```powershell
Get-Content logs\app.log -Tail 20
```
</details>

<details><summary>B3. Affiche les lignes 100 à 110.</summary>

```bash
sed -n '100,110p' logs/app.log        # ou : head -n 110 logs/app.log | tail -n 11
```
```powershell
Get-Content logs\app.log | Select-Object -Skip 99 -First 11
```
</details>

<details><summary>B4. Compte le nombre de lignes de chaque fichier de <code>logs/</code>.</summary>

```bash
wc -l logs/*
```
```powershell
Get-ChildItem logs | ForEach-Object { "{0} : {1} lignes" -f $_.Name, (Get-Content $_.FullName).Count }
```
</details>

<details><summary>B5. Suis <code>logs/app.log</code> en direct, et dans un 2ᵉ terminal ajoute-lui une ligne.</summary>

```bash
tail -f logs/app.log
# 2e terminal :
echo "2026-10-28 12:00:00 ERROR test en direct" >> ~/bac-a-sable/logs/app.log
# Ctrl+C pour arrêter de suivre
```
```powershell
Get-Content logs\app.log -Tail 5 -Wait
# 2e terminal :
Add-Content $HOME\bac-a-sable\logs\app.log "2026-10-28 12:00:00 ERROR test en direct"
```
</details>

<details><summary>B6. Lis <code>logs/access.log</code> page par page et cherche « 500 » dedans.</summary>

```bash
less logs/access.log        # puis tape /500 et Entrée ; n = suivant ; q = quitter
```
```powershell
Get-Content logs\access.log | more         # Espace = page suivante ; q = quitter
```
</details>

<details><summary>B7. Affiche la taille de <code>docs/projets/beta/gros-fichier.bin</code> en Mo.</summary>

```bash
ls -lh docs/projets/beta/gros-fichier.bin ; du -h docs/projets/beta/gros-fichier.bin
```
```powershell
"{0:N1} Mo" -f ((Get-Item docs\projets\beta\gros-fichier.bin).Length / 1MB)
```
</details>

<details><summary>B8. Calcule l'empreinte SHA-256 de <code>data/clients.csv</code>.</summary>

```bash
sha256sum data/clients.csv
```
```powershell
Get-FileHash data\clients.csv -Algorithm SHA256
```
</details>

---

## C. Fichiers et dossiers (7 exercices)

<details><summary>C1. Crée en une commande <code>tmp/a/b/c</code>.</summary>

```bash
mkdir -p tmp/a/b/c
```
```powershell
New-Item -ItemType Directory -Path tmp\a\b\c -Force
```
</details>

<details><summary>C2. Copie tout le dossier <code>config</code> dans <code>tmp/config-sauvegarde</code>.</summary>

```bash
cp -r config tmp/config-sauvegarde
```
```powershell
Copy-Item config tmp\config-sauvegarde -Recurse
```
</details>

<details><summary>C3. Renomme <code>tmp/config-sauvegarde/app.conf</code> en <code>app.conf.bak</code>.</summary>

```bash
mv tmp/config-sauvegarde/app.conf tmp/config-sauvegarde/app.conf.bak
```
```powershell
Rename-Item tmp\config-sauvegarde\app.conf app.conf.bak
```
</details>

<details><summary>C4. Trouve tous les fichiers <code>.txt</code> sous <code>docs</code>.</summary>

```bash
find docs -name "*.txt"
```
```powershell
Get-ChildItem docs -Recurse -Filter *.txt
```
</details>

<details><summary>C5. Trouve les fichiers de plus de 10 Mo du bac à sable.</summary>

```bash
find . -type f -size +10M
```
```powershell
Get-ChildItem -Recurse -File | Where-Object Length -gt 10MB
```
</details>

<details><summary>C6. Trouve les fichiers modifiés il y a plus de 30 jours.</summary>

```bash
find . -type f -mtime +30
```
```powershell
Get-ChildItem -Recurse -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30)
```
</details>

<details><summary>C7. Supprime <code>tmp/a</code> et tout ce qu'il contient… après avoir simulé la suppression.</summary>

```bash
ls -R tmp/a          # vérifier d'abord
rm -r tmp/a
```
```powershell
Remove-Item tmp\a -Recurse -WhatIf      # simulation : rien n'est supprimé
Remove-Item tmp\a -Recurse
```
</details>

---

## D. Droits et propriétaires (6 exercices)

<details><summary>D1. Affiche les droits et le propriétaire de <code>config/secret.txt</code>. Qu'est-ce qui ne va pas ?</summary>

```bash
ls -l config/secret.txt        # -rw-rw-rw- : tout le monde peut le lire ET le modifier !
stat config/secret.txt
```
```powershell
Get-Acl config\secret.txt | Format-List Owner, AccessToString
icacls config\secret.txt
```
</details>

<details><summary>D2. Rends <code>config/secret.txt</code> lisible et modifiable par toi seul.</summary>

```bash
chmod 600 config/secret.txt ; ls -l config/secret.txt     # -rw-------
```
```powershell
# Couper l'héritage des droits du dossier, puis ne donner l'accès qu'à toi-même
icacls config\secret.txt /inheritance:r /grant:r "${env:USERNAME}:(R,W)"
icacls config\secret.txt
```
</details>

<details><summary>D3. Lance <code>scripts/bonjour.sh</code> : pourquoi ça échoue ? Corrige.</summary>

```bash
./scripts/bonjour.sh          # Permission denied : pas de bit x
chmod +x scripts/bonjour.sh && ./scripts/bonjour.sh
# Alternative sans changer les droits : bash scripts/bonjour.sh
```
```powershell
.\scripts\bonjour.ps1         # peut être bloqué par la stratégie d'exécution
Get-ExecutionPolicy -List
Set-ExecutionPolicy -Scope Process Bypass ; .\scripts\bonjour.ps1     # pour cette session seulement
```
</details>

<details><summary>D4. Traduis <code>rwxr-x---</code> en octal, et <code>644</code> en lettres.</summary>

`rwxr-x---` = **750** (7 = 4+2+1, 5 = 4+1, 0). `644` = **rw-r--r--** (propriétaire lit/écrit, les autres lisent).
</details>

<details><summary>D5. Affiche ton utilisateur et tes groupes. Es-tu dans le groupe <code>docker</code> (Linux) / administrateur (Windows) ?</summary>

```bash
whoami ; id ; groups | grep -w docker
```
```powershell
whoami ; whoami /groups | Select-String "Administrateurs|Administrators"
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")
```
</details>

<details><summary>D6. Donne le droit d'exécution au propriétaire et au groupe sur tous les <code>.sh</code> de <code>scripts/</code>, et retire tout droit aux « autres ».</summary>

```bash
chmod ug+x,o-rwx scripts/*.sh ; ls -l scripts
```
```powershell
# Pas d'équivalent direct (pas de bit x sous Windows) : on retire le groupe "Utilisateurs" des ACL
Get-ChildItem scripts\*.ps1 | ForEach-Object { icacls $_.FullName /remove:g "*S-1-5-32-545" }   # S-1-5-32-545 = BUILTIN\Users
```
</details>

---

## E. Processus (9 exercices)

<details><summary>E1. Lance <code>scripts/poli.sh</code> (Linux) / <code>scripts/boucle.ps1</code> (Windows) en arrière-plan.</summary>

```bash
./scripts/poli.sh &          # le shell affiche [1] <PID>
jobs
```
```powershell
$p = Start-Process powershell -ArgumentList '-NoProfile', '-File', "$HOME\bac-a-sable\scripts\boucle.ps1" -WindowStyle Minimized -PassThru
$p.Id
```
</details>

<details><summary>E2. Trouve son PID par son nom.</summary>

```bash
pgrep -af poli.sh            # ou : ps aux | grep [p]oli.sh
```
```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*boucle.ps1*' | Select-Object ProcessId, CommandLine
```
</details>

<details><summary>E3. Arrête-le proprement (SIGTERM / arrêt normal).</summary>

```bash
kill <PID>                   # poli.sh affiche "SIGTERM recu : je ferme proprement"
```
```powershell
Stop-Process -Id $p.Id
```
</details>

<details><summary>E4. Lance <code>scripts/boucle.sh</code> en arrière-plan, et essaie de l'arrêter avec <code>kill</code>. Que se passe-t-il ?</summary>

```bash
./scripts/boucle.sh &
kill <PID>                   # "SIGTERM recu... et ignore !" : il continue
```
Le script intercepte (*trap*) SIGTERM et l'ignore. C'est ce que fait une application mal écrite, ou bloquée.
</details>

<details><summary>E5. Force son arrêt.</summary>

```bash
kill -9 <PID>                # SIGKILL : impossible à intercepter, mort immédiate
# ou par nom : pkill -9 -f boucle.sh
```
```powershell
Stop-Process -Id <PID> -Force          # ou : taskkill /PID <PID> /F
```
</details>

<details><summary>E6. Affiche les 5 processus qui consomment le plus de mémoire.</summary>

```bash
ps aux --sort=-%mem | head -n 6
```
```powershell
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 Name, Id, @{n='Mo';e={[math]::Round($_.WorkingSet/1MB)}}
```
</details>

<details><summary>E7. Ouvre la vue temps réel des processus, trie par CPU, puis quitte.</summary>

```bash
htop        # F6 pour trier, F9 pour tuer, q pour quitter  (ou : top, puis P pour trier par CPU)
```
```powershell
taskmgr     # le Gestionnaire des tâches ; en console : Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
```
</details>

<details><summary>E8. Lance un serveur web sur le port 8099 et trouve quel processus écoute sur ce port.</summary>

```bash
python3 -m http.server 8099 &
ss -tlnp | grep 8099          # (sudo pour voir le nom des processus d'autres utilisateurs)
kill %1
```
```powershell
$srv = Start-Job { python -m http.server 8099 }      # si Python est installé sous Windows ; sinon : un autre port déjà ouvert
Get-NetTCPConnection -LocalPort 8099 -State Listen | ForEach-Object { Get-Process -Id $_.OwningProcess }
Stop-Job $srv ; Remove-Job $srv
```
</details>

<details><summary>E9. Lance une commande qui continue même si tu fermes le terminal.</summary>

```bash
nohup ./scripts/poli.sh > /tmp/poli.log 2>&1 &
# ferme et rouvre le terminal, puis : pgrep -af poli.sh  ;  pkill -f poli.sh
```
```powershell
Start-Process powershell -ArgumentList '-NoProfile', '-File', "$HOME\bac-a-sable\scripts\boucle.ps1" -WindowStyle Hidden
# processus indépendant de la console. Pour l'arrêter : voir E2 puis E5
```
</details>

---

## F. Chercher dans le texte (7 exercices)

<details><summary>F1. Affiche les lignes ERROR de <code>logs/app.log</code>.</summary>

```bash
grep ERROR logs/app.log
```
```powershell
Select-String -Path logs\app.log -Pattern ERROR
```
</details>

<details><summary>F2. Compte-les.</summary>

```bash
grep -c ERROR logs/app.log
```
```powershell
(Select-String -Path logs\app.log -Pattern ERROR).Count
```
</details>

<details><summary>F3. Affiche les lignes qui ne sont ni INFO ni DEBUG.</summary>

```bash
grep -vE "INFO|DEBUG" logs/app.log
```
```powershell
Select-String -Path logs\app.log -Pattern "INFO|DEBUG" -NotMatch
```
</details>

<details><summary>F4. Combien de lignes par niveau (INFO, WARN, ERROR, DEBUG) ?</summary>

```bash
awk '{print $3}' logs/app.log | sort | uniq -c | sort -rn
```
```powershell
Get-Content logs\app.log | ForEach-Object { ($_ -split '\s+')[2] } | Group-Object | Sort-Object Count -Descending | Select-Object Count, Name
```
</details>

<details><summary>F5. Cherche « password » dans tous les fichiers du bac à sable (sécurité !).</summary>

```bash
grep -rn password .
```
```powershell
Get-ChildItem -Recurse -File -Exclude *.bin | Select-String -Pattern password
```
Un mot de passe dans un log est une **fuite** : c'est ce que détecte gitleaks au module 07.
</details>

<details><summary>F6. Dans <code>logs/access.log</code>, quelles sont les 3 IP qui font le plus de requêtes ?</summary>

```bash
cut -d' ' -f1 logs/access.log | sort | uniq -c | sort -rn | head -3
```
```powershell
Get-Content logs\access.log | ForEach-Object { ($_ -split ' ')[0] } | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 Count, Name
```
</details>

<details><summary>F7. Remplace <code>log_level=INFO</code> par <code>log_level=DEBUG</code> dans <code>config/app.conf</code>.</summary>

```bash
sed -i 's/log_level=INFO/log_level=DEBUG/' config/app.conf && grep log_level config/app.conf
```
```powershell
(Get-Content config\app.conf) -replace 'log_level=INFO', 'log_level=DEBUG' | Set-Content config\app.conf -Encoding UTF8
Select-String -Path config\app.conf -Pattern log_level
```
</details>

---

## G. Données, disque, système (5 exercices)

<details><summary>G1. Affiche les clients de Paris, puis la somme de tous les soldes.</summary>

```bash
grep ';Paris;' data/clients.csv
awk -F';' 'NR > 1 { s += $4 } END { print s }' data/clients.csv
```
```powershell
Import-Csv data\clients.csv -Delimiter ';' | Where-Object ville -eq 'Paris'
(Import-Csv data\clients.csv -Delimiter ';' | Measure-Object -Property solde -Sum).Sum
```
</details>

<details><summary>G2. Affiche l'espace libre des disques.</summary>

```bash
df -h
```
```powershell
Get-PSDrive -PSProvider FileSystem
```
</details>

<details><summary>G3. Affiche la taille de chaque sous-dossier de <code>docs/projets</code>, du plus gros au plus petit.</summary>

```bash
du -sh docs/projets/* | sort -rh
```
```powershell
Get-ChildItem docs\projets -Directory | ForEach-Object {
  [pscustomobject]@{ Dossier = $_.Name; Mo = [math]::Round((Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 2) }
} | Sort-Object Mo -Descending
```
</details>

<details><summary>G4. Affiche la mémoire totale et libre, et le nombre de cœurs.</summary>

```bash
free -h ; nproc
```
```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object @{n='TotalGo';e={[math]::Round($_.TotalVisibleMemorySize/1MB,1)}}, @{n='LibreGo';e={[math]::Round($_.FreePhysicalMemory/1MB,1)}}
(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
```
</details>

<details><summary>G5. Affiche le système, sa version, et depuis combien de temps il tourne.</summary>

```bash
cat /etc/os-release | head -2 ; uname -r ; uptime -p
```
```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, LastBootUpTime
(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
```
</details>

---

## H. Réseau (3 exercices)

<details><summary>H1. Affiche tes adresses IP.</summary>

```bash
ip -br a
```
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, IPAddress
```
</details>

<details><summary>H2. Vérifie que github.com répond en HTTPS (port 443) et résous son nom.</summary>

```bash
nc -zv github.com 443 ; dig +short github.com
```
```powershell
Test-NetConnection github.com -Port 443 ; Resolve-DnsName github.com
```
</details>

<details><summary>H3. Interroge l'API publique de GitHub et affiche le nombre de dépôts publics de ton compte.</summary>

```bash
curl -s https://api.github.com/users/tadeyayaoye | jq .public_repos
```
```powershell
(Invoke-RestMethod https://api.github.com/users/tadeyayaoye).public_repos     # JSON → objet directement
```
</details>

---

## 🏁 Challenge chronométré (≈ 15 min, sans regarder les réponses)

Dans chaque shell, en **une seule ligne** chacune :

1. Archive `logs/` dans `archives/logs-<date du jour>.tar.gz` (Linux) / `.zip` (PowerShell).
2. Écris dans `tmp/rapport.txt` le nombre d'ERROR et de WARN de `app.log`, puis affiche le fichier.
3. Trouve le PID du processus qui consomme le plus de CPU, et affiche sa ligne de commande complète.
4. Liste les 3 plus gros fichiers du bac à sable avec leur taille.
5. Supprime tous les fichiers `.txt` de `docs/projets/alpha` modifiés il y a plus de 30 jours (simulation d'abord !).

<details><summary>Réponses possibles</summary>

```bash
tar czf archives/logs-$(date +%F).tar.gz logs/
printf 'ERROR=%s WARN=%s\n' "$(grep -c ERROR logs/app.log)" "$(grep -c WARN logs/app.log)" | tee tmp/rapport.txt
ps -eo pid,%cpu,cmd --sort=-%cpu | sed -n 2p
find . -type f -printf '%s %p\n' | sort -rn | head -3 | numfmt --to=iec --field=1
find docs/projets/alpha -name '*.txt' -mtime +30 -print     # puis la même avec -delete
```
```powershell
Compress-Archive logs "archives\logs-$(Get-Date -Format yyyy-MM-dd).zip"
"ERROR=$((sls ERROR logs\app.log).Count) WARN=$((sls WARN logs\app.log).Count)" | Tee-Object tmp\rapport.txt
gps | ? Path | sort CPU -desc | select -first 1 | % { (gcim Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine }   # "? Path" écarte Idle/System
gci -Recurse -File | sort Length -desc | select -first 3 Name, @{n='Mo';e={[math]::Round($_.Length/1MB,1)}}
gci docs\projets\alpha -Filter *.txt | ? LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -WhatIf    # puis sans -WhatIf
```
</details>

---

## Nettoyage

```bash
rm -rf ~/bac-a-sable
```
```powershell
Remove-Item $HOME\bac-a-sable -Recurse -Force
```
