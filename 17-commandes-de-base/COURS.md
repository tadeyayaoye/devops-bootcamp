# Module 17 — Les commandes de base : Linux (bash) et Windows (PowerShell)

> **Objectif** : retrouver les réflexes de la ligne de commande au quotidien — fichiers, lecture, droits, processus, services, disque, réseau, texte — avec, pour chaque besoin, **la commande Linux et son équivalent PowerShell**.
>
> **Durée** : cours ~1 h 30 · labs ~2 h · quiz 30 min · *Module indépendant : à faire quand tu veux, idéalement tôt.*

---

## 1. Deux philosophies

| | Linux (bash) | PowerShell |
|---|---|---|
| Ce qui circule dans un pipe `\|` | du **texte** | des **objets** (avec des propriétés) |
| Style des commandes | courtes, historiques (`ls`, `grep`, `ps`) | **Verbe-Nom** (`Get-ChildItem`, `Select-String`, `Get-Process`) |
| Options | `-l`, `--all` | `-Path`, `-Force`, `-Recurse` (abréviables) |
| Sensibilité à la casse | **oui** (`Fichier` ≠ `fichier`) | **non** pour les commandes et (sous Windows) les chemins |
| Chemins | `/home/tayaya/fichier.txt` | `C:\Users\tayay\fichier.txt` (les `/` marchent aussi) |
| Variables | `NOM=valeur`, `$NOM` | `$nom = "valeur"`, `$nom` ; environnement : `$env:PATH` |
| Aide | `man ls`, `ls --help` | `Get-Help Get-ChildItem -Examples` |

**Pourquoi des objets change tout** : en bash, pour « les 5 processus qui consomment le plus de mémoire », on découpe du texte. En PowerShell, on trie sur une **propriété** :

```bash
ps aux --sort=-%mem | head -6
```
```powershell
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 Name, Id, WorkingSet
```

### Les alias PowerShell (pièges compris)

PowerShell définit des **alias** pour accueillir les habitués de Linux : `ls`, `cat`, `cp`, `mv`, `rm`, `pwd`, `cd`, `ps`, `kill`… Ils **lancent les cmdlets PowerShell**, pas les commandes Linux : `ls -la` **ne marche pas** (`-la` n'est pas un paramètre de `Get-ChildItem`). Utilise les alias pour taper vite, mais apprends le vrai nom de la cmdlet. Liste : `Get-Alias`.

⚠ Dans **Windows PowerShell 5.1** (celui installé par défaut), `curl` et `wget` sont des alias d'`Invoke-WebRequest`. Pour le vrai curl : `curl.exe`. **PowerShell 7** (`pwsh`, à installer : `winget install Microsoft.PowerShell`) a supprimé ces alias et fonctionne aussi sous Linux.

---

## 2. Se repérer et obtenir de l'aide

| Besoin | Linux | PowerShell |
|---|---|---|
| Où suis-je ? | `pwd` | `Get-Location` (alias `pwd`) |
| Aller dans un dossier | `cd /var/log` · `cd ~` · `cd -` (précédent) · `cd ..` | `Set-Location C:\Windows` (alias `cd`) · `cd ~` · `cd ..` |
| Aide d'une commande | `man tail` · `tail --help` | `Get-Help Get-Content -Full` · `-Examples` |
| Trouver une commande | `apropos disk` · `which kubectl` · `type ls` | `Get-Command *service*` · `Get-Command kubectl` |
| Qu'est-ce que ce truc ? | `file image.png` | `Get-Item fichier \| Format-List *` |
| Propriétés d'un objet | — | `Get-Process \| Get-Member` |
| Historique | `history` · **Ctrl+R** (recherche) · `!!` (dernière commande) | `Get-History` · **Ctrl+R** (PSReadLine) · `Invoke-History <n>` |
| Effacer l'écran | `clear` · Ctrl+L | `Clear-Host` (alias `cls`) · Ctrl+L |

> 💡 **Tab** complète les commandes et les chemins dans les deux shells. **Ctrl+C** interrompt la commande en cours.

---

## 3. Fichiers et dossiers

| Besoin | Linux | PowerShell |
|---|---|---|
| Lister | `ls` · `ls -l` (détails) · `ls -la` (avec cachés) · `ls -lh` (tailles lisibles) | `Get-ChildItem` (alias `ls`, `dir`, `gci`) · `-Force` (cachés) |
| Trier par date / taille | `ls -lt` · `ls -lS` | `gci \| Sort-Object LastWriteTime -Descending` · `Sort-Object Length` |
| Récursif | `ls -R` · `tree` | `gci -Recurse` · `tree /F` (commande Windows) |
| Créer un dossier | `mkdir -p a/b/c` | `New-Item -ItemType Directory -Path a\b\c -Force` (alias `mkdir`) |
| Créer un fichier vide | `touch fichier.txt` | `New-Item fichier.txt -ItemType File` |
| Copier | `cp a b` · `cp -r dossier/ copie/` | `Copy-Item a b` · `Copy-Item dossier copie -Recurse` |
| Déplacer / renommer | `mv a b` | `Move-Item a b` · `Rename-Item a b` |
| Supprimer | `rm fichier` · `rm -r dossier` · `rm -rf dossier` ⚠ | `Remove-Item fichier` · `Remove-Item dossier -Recurse -Force` ⚠ |
| Simuler avant d'agir | `rm -i` (confirmation) | `Remove-Item ... -WhatIf` ✅ (montre ce qui serait fait) |
| Chercher par nom | `find /var/log -name "*.log"` | `gci C:\Logs -Recurse -Filter *.log` |
| Chercher par taille / date | `find . -size +100M` · `find . -mtime -1` (modifiés < 1 j) | `gci -Recurse -File \| ? Length -gt 100MB` · `? LastWriteTime -gt (Get-Date).AddDays(-1)` |
| Lien symbolique | `ln -s cible lien` | `New-Item -ItemType SymbolicLink -Path lien -Target cible` (admin ou mode développeur) |
| Existe ? | `test -f f && echo oui` · `[[ -d dossier ]]` | `Test-Path f` · `Test-Path dossier -PathType Container` |

> ⚠ Il n'y a **pas de corbeille** en ligne de commande, dans les deux mondes. `rm -rf` / `Remove-Item -Recurse -Force` sont définitifs. Relis toujours le chemin, surtout avec une variable (`rm -rf "$DOSSIER/"` avec `$DOSSIER` vide = `rm -rf /` !).

---

## 4. Lire et surveiller un fichier

| Besoin | Linux | PowerShell |
|---|---|---|
| Afficher tout | `cat fichier` | `Get-Content fichier` (alias `cat`, `gc`, `type`) |
| **Les 20 premières lignes** | `head -n 20 fichier` (ou `head -20`) | `Get-Content fichier -TotalCount 20` (ou `-Head 20`) |
| **Les 20 dernières lignes** | `tail -n 20 fichier` | `Get-Content fichier -Tail 20` |
| **Suivre en direct** (logs) | `tail -f fichier` · `tail -F` (suit la rotation) | `Get-Content fichier -Tail 10 -Wait` |
| Les lignes 100 à 120 | `sed -n '100,120p' fichier` | `Get-Content fichier \| Select-Object -Skip 99 -First 21` |
| Page par page | `less fichier` (`/mot` cherche, `q` quitte, `G` fin) | `Get-Content fichier \| more` · `Out-Host -Paging` |
| Compter les lignes | `wc -l fichier` | `(Get-Content fichier).Count` · `Get-Content f \| Measure-Object -Line` |
| Taille | `ls -lh f` · `du -h f` | `(Get-Item f).Length` · `"{0:N1} Mo" -f ((Get-Item f).Length/1MB)` |
| Fichier binaire en hexa | `xxd f \| head` · `hexdump -C` | `Format-Hex f \| Select-Object -First 5` |
| Comparer deux fichiers | `diff a b` · `diff -u a b` | `Compare-Object (gc a) (gc b)` |
| Empreinte | `sha256sum f` | `Get-FileHash f -Algorithm SHA256` |

---

## 5. Droits et propriétaires

### Linux : le modèle `rwx`

```
-rwxr-x---  1  tayaya  devops  4096  oct 28 10:00  deploy.sh
│└┬┘└┬┘└┬┘     │       │
│ u  g  o      │       └ groupe propriétaire
│              └ utilisateur propriétaire
└ type : - fichier, d dossier, l lien
```

| Lettre | Fichier | Dossier | Valeur |
|---|---|---|---|
| `r` | lire | lister le contenu | 4 |
| `w` | modifier | créer / supprimer dedans | 2 |
| `x` | exécuter | entrer dedans (`cd`) | 1 |

`rwxr-x---` = 7 (4+2+1) / 5 (4+1) / 0 → **750**. Valeurs courantes : `644` (fichier normal), `600` (secret : clé SSH, kubeconfig), `755` (script, dossier), `700` (dossier privé).

| Besoin | Linux | PowerShell (Windows) |
|---|---|---|
| **Voir les droits** | `ls -l fichier` · `stat fichier` | `Get-Acl fichier \| Format-List` · `icacls fichier` |
| Rendre exécutable | `chmod +x script.sh` | — (pas de bit exécutable ; c'est l'extension + l'*execution policy*) |
| Modifier (octal) | `chmod 640 fichier` | `icacls fichier /grant "Utilisateur:(R)"` |
| Modifier (symbolique) | `chmod u+x,g-w,o-rwx fichier` | `icacls fichier /remove "Utilisateurs"` |
| Récursif | `chmod -R 750 dossier` | `icacls dossier /grant "Groupe:(OI)(CI)RX" /T` |
| Changer le propriétaire | `sudo chown tayaya:devops fichier` | `icacls fichier /setowner "Utilisateur"` (admin) |
| Qui suis-je, mes groupes | `whoami` · `id` · `groups` | `whoami` · `whoami /groups` · `[Security.Principal.WindowsIdentity]::GetCurrent().Name` |
| Agir en administrateur | `sudo commande` · `sudo -i` | Terminal lancé « en tant qu'administrateur » · `Start-Process pwsh -Verb RunAs` |
| Droits par défaut des nouveaux fichiers | `umask` (souvent 022) | héritage des ACL du dossier parent |

> Windows utilise des **ACL** (listes de contrôle d'accès) : une liste d'entrées « tel utilisateur/groupe a tel droit (lecture, modification, contrôle total…) », héritées des dossiers parents. Plus fin, mais plus verbeux que `rwx`. Linux a aussi des ACL (`getfacl`, `setfacl`) quand `rwx` ne suffit pas — on les a croisées au module 05 (paquet `acl` pour Ansible).

**Exécution des scripts PowerShell** : la stratégie d'exécution (`Get-ExecutionPolicy`) peut bloquer les `.ps1`. Pour la session en cours seulement : `Set-ExecutionPolicy -Scope Process Bypass` (ou `powershell -ExecutionPolicy Bypass -File script.ps1`). Ne baisse pas la stratégie pour toute la machine sans raison.

---

## 6. Processus

| Besoin | Linux | PowerShell |
|---|---|---|
| Lister | `ps aux` · `ps -ef` · `ps -u tayaya` | `Get-Process` (alias `ps`, `gps`) |
| Trouver par nom | `pgrep -a python` · `ps aux \| grep [p]ython` | `Get-Process -Name python*` |
| Détail d'un processus | `ps -p 1234 -o pid,ppid,user,%cpu,%mem,etime,cmd` | `Get-Process -Id 1234 \| Format-List *` |
| Ligne de commande complète | `cat /proc/1234/cmdline \| tr '\0' ' '` · `ps -o cmd -p 1234` | `Get-CimInstance Win32_Process -Filter "ProcessId=1234" \| Select CommandLine` |
| Temps réel | `top` · `htop` (`F9` tuer, `F6` trier, `q` quitter) | `while ($true) { cls; gps \| sort CPU -desc \| select -first 10; sleep 2 }` · Gestionnaire des tâches |
| Les plus gourmands | `ps aux --sort=-%mem \| head` · `--sort=-%cpu` | `gps \| sort WorkingSet -desc \| select -first 5` · `sort CPU -desc` |
| **Arrêter proprement** | `kill 1234` (= `kill -15`, SIGTERM) | `Stop-Process -Id 1234` |
| **Forcer l'arrêt** | `kill -9 1234` (SIGKILL) | `Stop-Process -Id 1234 -Force` · `taskkill /PID 1234 /F` |
| Arrêter par nom | `pkill -f boucle.sh` · `killall nginx` | `Stop-Process -Name notepad` · `gps boucle* \| Stop-Process -Force` |
| Arbre de processus (et enfants) | `pstree -p` · `kill -- -<pgid>` | `taskkill /PID 1234 /T /F` (`/T` = avec les enfants) |
| Qui utilise ce port ? | `sudo ss -tlnp \| grep :8080` · `sudo lsof -i :8080` | `Get-NetTCPConnection -LocalPort 8080 \| Select OwningProcess` puis `Get-Process -Id <pid>` |
| Qui bloque ce fichier ? | `lsof /chemin/fichier` · `fuser -v fichier` | (Resource Monitor / `handle.exe` de Sysinternals) |

> 🔁 Rappel du module 00 : **SIGTERM** (15) demande poliment (l'application peut finir son travail), **SIGKILL** (9) tue immédiatement sans laisser l'application nettoyer. Toujours essayer `kill` (ou `Stop-Process` sans `-Force`) **avant** `kill -9`. Sous Windows, `Stop-Process` sans `-Force` peut demander confirmation pour certains processus, et `-Force` termine sans délai.

### Lancer en arrière-plan

| Besoin | Linux | PowerShell |
|---|---|---|
| Lancer en arrière-plan | `commande &` | `Start-Job { commande }` · `Start-Process prog -WindowStyle Hidden` |
| Lister les tâches | `jobs` | `Get-Job` |
| Ramener au premier plan | `fg %1` · `Ctrl+Z` puis `bg` | `Receive-Job -Id 1 -Wait` |
| Survivre à la fermeture du terminal | `nohup commande > log 2>&1 &` · `setsid` · `tmux` | `Start-Process` (processus indépendant) |
| Attendre un processus | `wait 1234` | `Wait-Process -Id 1234` |

---

## 7. Services

| Besoin | Linux (systemd) | PowerShell (services Windows) |
|---|---|---|
| Lister | `systemctl list-units --type=service` · `--state=running` | `Get-Service` · `Get-Service \| ? Status -eq Running` |
| État | `systemctl status docker` | `Get-Service -Name Spooler` |
| Démarrer / arrêter / redémarrer | `sudo systemctl start\|stop\|restart docker` | `Start-Service`, `Stop-Service`, `Restart-Service -Name Spooler` (admin) |
| Au démarrage | `sudo systemctl enable --now docker` · `disable` | `Set-Service -Name Spooler -StartupType Automatic` |
| Logs | `journalctl -u docker -f` · `--since "1 hour ago"` | `Get-WinEvent -LogName System -MaxEvents 20` · `Get-EventLog -LogName Application -Newest 20` (5.1) |

---

## 8. Disque, mémoire, système

| Besoin | Linux | PowerShell |
|---|---|---|
| Espace disque | `df -h` | `Get-PSDrive -PSProvider FileSystem` · `Get-Volume` |
| Taille d'un dossier | `du -sh dossier` | `"{0:N1} Mo" -f ((gci dossier -Recurse -File \| Measure-Object Length -Sum).Sum / 1MB)` |
| Les plus gros éléments | `du -h --max-depth=1 . \| sort -h \| tail` | `gci -Directory \| % { [pscustomobject]@{Nom=$_.Name; Mo=[math]::Round((gci $_ -Recurse -File \| measure Length -Sum).Sum/1MB,1)} } \| sort Mo` |
| Mémoire | `free -h` | `Get-CimInstance Win32_OperatingSystem \| Select FreePhysicalMemory, TotalVisibleMemorySize` |
| CPU | `nproc` · `lscpu` | `(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors` |
| Système | `uname -a` · `cat /etc/os-release` · `hostname` · `uptime` | `Get-ComputerInfo \| Select OsName, OsVersion` · `hostname` · `(Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime` |
| Date | `date` · `date +%F_%H%M` | `Get-Date` · `Get-Date -Format "yyyy-MM-dd_HHmm"` |
| Variables d'environnement | `env` · `echo $PATH` · `export VAR=x` | `Get-ChildItem env:` · `$env:PATH` · `$env:VAR = "x"` |

---

## 9. Réseau

| Besoin | Linux | PowerShell |
|---|---|---|
| Mes adresses IP | `ip -br a` · `hostname -I` | `Get-NetIPAddress -AddressFamily IPv4 \| Select InterfaceAlias, IPAddress` · `ipconfig` |
| Routes | `ip route` | `Get-NetRoute` · `route print` |
| Ping | `ping -c 4 github.com` | `Test-Connection github.com -Count 4` · `ping github.com` |
| Un port est-il ouvert ? | `nc -zv hote 5432` | `Test-NetConnection hote -Port 5432` |
| Ports en écoute | `ss -tlnp` | `Get-NetTCPConnection -State Listen` |
| Résolution DNS | `dig +short github.com` · `nslookup` | `Resolve-DnsName github.com` · `nslookup` |
| Requête HTTP | `curl -s http://localhost:8000/healthz` · `curl -I` (en-têtes) | `Invoke-RestMethod http://localhost:8000/healthz` (JSON → objet) · `Invoke-WebRequest` · `curl.exe` |
| Télécharger | `curl -LO url` · `wget url` | `Invoke-WebRequest url -OutFile fichier` |
| Copier vers un serveur | `scp f user@hote:/tmp/` · `rsync -av` | `scp` (OpenSSH inclus dans Windows) · `Copy-Item -ToSession` |
| Se connecter | `ssh user@hote` | `ssh user@hote` |

---

## 10. Chercher et transformer du texte

| Besoin | Linux | PowerShell |
|---|---|---|
| Lignes contenant un mot | `grep ERROR app.log` | `Select-String -Path app.log -Pattern ERROR` (alias `sls`) |
| Sans tenir compte de la casse | `grep -i error` | `sls -Pattern error` (insensible par défaut) · `-CaseSensitive` |
| Ne PAS contenir | `grep -v DEBUG` | `sls -Pattern DEBUG -NotMatch` |
| Compter | `grep -c ERROR app.log` | `(sls ERROR app.log).Count` |
| Récursif dans un dossier | `grep -rn "password" .` | `gci -Recurse -File \| sls "password"` |
| Avec contexte | `grep -C 2 ERROR` (2 lignes avant/après) | `sls ERROR -Context 2` |
| Expression régulière | `grep -E "ERROR\|WARN"` | `sls "ERROR\|WARN"` |
| Remplacer | `sed 's/ancien/nouveau/g' f` · `sed -i` (sur place) | `(gc f) -replace 'ancien','nouveau' \| Set-Content f` |
| Colonne d'un CSV | `cut -d';' -f2 f.csv` · `awk -F';' '{print $2}'` | `Import-Csv f.csv -Delimiter ';' \| Select nom` |
| Trier / dédoublonner | `sort f \| uniq` · `sort -u` · `sort -n` (numérique) | `gc f \| Sort-Object -Unique` · `Sort-Object { [int]$_ }` |
| Compter les occurrences | `sort \| uniq -c \| sort -rn` | `Group-Object \| Sort-Object Count -Descending` |
| Somme d'une colonne | `awk -F';' '{s+=$4} END {print s}' f` | `(Import-Csv f -Delimiter ';' \| Measure-Object solde -Sum).Sum` |
| JSON | `jq '.items[].name'` | `ConvertFrom-Json` · `ConvertTo-Json` |

---

## 11. Redirections et enchaînements

| Besoin | Linux | PowerShell |
|---|---|---|
| Écrire dans un fichier (écrase) | `commande > sortie.txt` | `commande > sortie.txt` · `\| Out-File sortie.txt` · `\| Set-Content` |
| Ajouter à la fin | `>> sortie.txt` | `>> sortie.txt` · `\| Add-Content sortie.txt` |
| Erreurs vers un fichier | `2> erreurs.txt` | `2> erreurs.txt` |
| Tout (sortie + erreurs) | `> tout.txt 2>&1` · `&> tout.txt` | `*> tout.txt` |
| Jeter la sortie | `> /dev/null 2>&1` | `\| Out-Null` · `> $null` |
| Afficher ET écrire | `\| tee fichier` · `tee -a` | `\| Tee-Object fichier` · `-Append` |
| Enchaîner si succès | `cmd1 && cmd2` | `cmd1; if ($?) { cmd2 }` (5.1) · `cmd1 && cmd2` (PowerShell 7) |
| Enchaîner si échec | `cmd1 \|\| cmd2` | `if (-not $?) { cmd2 }` · `\|\|` (PowerShell 7) |
| Code retour | `echo $?` (0 = succès) | `$?` (booléen) · `$LASTEXITCODE` (programmes externes) |
| Résultat d'une commande dans une variable | `n=$(wc -l < f)` | `$n = (gc f).Count` |
| Boucle sur des fichiers | `for f in *.log; do gzip "$f"; done` | `gci *.log \| ForEach-Object { Compress-Archive $_ "$($_.Name).zip" }` |

> ⚠ Encodage : dans Windows PowerShell 5.1, `>` produit de l'**UTF-16**, et `Set-Content` utilise l'encodage ANSI, ce qui donne des fichiers illisibles par les outils Linux. Précise `-Encoding utf8` (`Out-File -Encoding utf8`). PowerShell 7 écrit de l'UTF-8 par défaut.

---

## 12. Archives

| Besoin | Linux | PowerShell |
|---|---|---|
| Créer un `.tar.gz` | `tar czf archive.tar.gz dossier/` | `tar -czf archive.tar.gz dossier` (tar est inclus dans Windows 10+) |
| Lister / extraire | `tar tzf archive.tar.gz` · `tar xzf archive.tar.gz -C dest/` | `tar -tzf …` · `tar -xzf archive.tar.gz -C dest` |
| Zip | `zip -r archive.zip dossier/` · `unzip archive.zip` | `Compress-Archive dossier archive.zip` · `Expand-Archive archive.zip dest` |
| Compresser un fichier | `gzip f` (→ `f.gz`) · `gunzip f.gz` · `zcat f.gz` | `Compress-Archive f f.zip` |

---

## 13. Les 25 commandes à connaître par cœur

| # | Linux | PowerShell |
|---|---|---|
| 1 | `ls -la` | `gci -Force` |
| 2 | `cd`, `pwd` | `cd`, `pwd` |
| 3 | `mkdir -p` | `New-Item -ItemType Directory -Force` |
| 4 | `cp -r`, `mv`, `rm -r` | `Copy-Item -Recurse`, `Move-Item`, `Remove-Item -Recurse` |
| 5 | `cat` | `Get-Content` |
| 6 | `head -n 20` | `Get-Content -TotalCount 20` |
| 7 | `tail -n 20`, `tail -f` | `Get-Content -Tail 20`, `-Wait` |
| 8 | `grep -i`, `grep -r` | `Select-String`, `gci -Recurse \| sls` |
| 9 | `find -name` | `gci -Recurse -Filter` |
| 10 | `wc -l` | `(gc f).Count` |
| 11 | `ls -l`, `stat` | `Get-Acl`, `icacls` |
| 12 | `chmod`, `chown` | `icacls /grant`, `/setowner` |
| 13 | `ps aux`, `pgrep` | `Get-Process` |
| 14 | `top` / `htop` | Gestionnaire des tâches / `gps \| sort CPU -desc` |
| 15 | `kill`, `kill -9`, `pkill` | `Stop-Process`, `-Force`, `-Name` |
| 16 | `systemctl status/restart` | `Get-Service`, `Restart-Service` |
| 17 | `journalctl -u` | `Get-WinEvent` |
| 18 | `df -h`, `du -sh` | `Get-PSDrive`, `Measure-Object -Sum` |
| 19 | `free -h` | `Win32_OperatingSystem` |
| 20 | `ip a`, `ss -tlnp` | `Get-NetIPAddress`, `Get-NetTCPConnection` |
| 21 | `ping`, `nc -zv` | `Test-Connection`, `Test-NetConnection -Port` |
| 22 | `curl` | `Invoke-RestMethod` / `curl.exe` |
| 23 | `sudo` | terminal administrateur |
| 24 | `> >> 2>&1 \| tee` | `> >> *> \| Tee-Object` |
| 25 | `history`, Ctrl+R | `Get-History`, Ctrl+R |
