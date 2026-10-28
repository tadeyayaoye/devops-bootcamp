# Module 17 — Quiz express : « quelle commande pour… ? »

Réponds à voix haute **en Linux puis en PowerShell**, sans regarder. Objectif : moins de 10 secondes par question.

<details><summary>1. Afficher les 20 premières lignes d'un fichier</summary>

`head -n 20 f` · `Get-Content f -TotalCount 20`
</details>

<details><summary>2. Suivre un fichier de log en direct</summary>

`tail -f f` · `Get-Content f -Tail 10 -Wait`
</details>

<details><summary>3. Voir les droits d'un fichier</summary>

`ls -l f` (ou `stat f`) · `Get-Acl f | Format-List` (ou `icacls f`)
</details>

<details><summary>4. Rendre un fichier lisible uniquement par son propriétaire</summary>

`chmod 600 f` · `icacls f /inheritance:r /grant:r "${env:USERNAME}:(R,W)"`
</details>

<details><summary>5. Trouver le PID d'un processus par son nom</summary>

`pgrep -a nom` · `Get-Process -Name nom`
</details>

<details><summary>6. Arrêter un processus proprement, puis de force</summary>

`kill PID` puis `kill -9 PID` · `Stop-Process -Id PID` puis `Stop-Process -Id PID -Force`
</details>

<details><summary>7. Pourquoi essayer <code>kill</code> avant <code>kill -9</code> ?</summary>

SIGTERM laisse l'application finir proprement (fermer ses fichiers et connexions, terminer les requêtes en cours). SIGKILL la tue instantanément, sans nettoyage : risque de données corrompues ou de fichiers verrouillés.
</details>

<details><summary>8. Les 5 processus les plus gourmands en mémoire</summary>

`ps aux --sort=-%mem | head -6` · `Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5`
</details>

<details><summary>9. Quel processus écoute sur le port 8080 ?</summary>

`ss -tlnp | grep :8080` (ou `lsof -i :8080`) · `Get-NetTCPConnection -LocalPort 8080 | Select OwningProcess`
</details>

<details><summary>10. Chercher « ERROR » dans un fichier, sans tenir compte de la casse</summary>

`grep -i error f` · `Select-String -Path f -Pattern error` (insensible par défaut)
</details>

<details><summary>11. Chercher un mot dans tous les fichiers d'un dossier</summary>

`grep -rn mot .` · `Get-ChildItem -Recurse -File | Select-String mot`
</details>

<details><summary>12. Trouver les fichiers de plus de 100 Mo</summary>

`find . -type f -size +100M` · `Get-ChildItem -Recurse -File | Where-Object Length -gt 100MB`
</details>

<details><summary>13. Espace disque libre, et taille d'un dossier</summary>

`df -h` et `du -sh dossier` · `Get-PSDrive` et `(Get-ChildItem dossier -Recurse -File | Measure-Object Length -Sum).Sum`
</details>

<details><summary>14. Créer une arborescence de dossiers en une commande</summary>

`mkdir -p a/b/c` · `New-Item -ItemType Directory a\b\c -Force`
</details>

<details><summary>15. Supprimer un dossier et son contenu, en simulant d'abord</summary>

`ls -R dossier` puis `rm -r dossier` · `Remove-Item dossier -Recurse -WhatIf` puis sans `-WhatIf`
</details>

<details><summary>16. Rediriger la sortie ET les erreurs dans un fichier</summary>

`cmd > tout.log 2>&1` · `cmd *> tout.log`
</details>

<details><summary>17. Exécuter une 2ᵉ commande seulement si la 1ʳᵉ a réussi</summary>

`cmd1 && cmd2` · PowerShell 7 : `cmd1 && cmd2` ; 5.1 : `cmd1; if ($?) { cmd2 }`
</details>

<details><summary>18. Redémarrer un service et voir ses logs</summary>

`sudo systemctl restart nginx` puis `journalctl -u nginx -f` · `Restart-Service -Name Spooler` puis `Get-WinEvent -LogName System -MaxEvents 20`
</details>

<details><summary>19. Tester si un port distant est ouvert</summary>

`nc -zv hote 5432` · `Test-NetConnection hote -Port 5432`
</details>

<details><summary>20. Pourquoi <code>ls -la</code> ne marche pas dans PowerShell, et <code>curl</code> se comporte bizarrement dans Windows PowerShell 5.1 ?</summary>

`ls` est un alias de `Get-ChildItem`, qui ne connaît pas `-la` (l'équivalent est `-Force`). Dans 5.1, `curl` est un alias d'`Invoke-WebRequest` : pour le vrai curl, taper `curl.exe` (ou utiliser PowerShell 7, qui a supprimé cet alias).
</details>
