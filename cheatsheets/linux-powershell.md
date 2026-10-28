# Linux ↔ PowerShell — fiche mémo

Version détaillée, thème par thème : [module 17, COURS.md](../17-commandes-de-base/COURS.md).

```bash
# ---------- Linux (bash) ----------
ls -la ; cd ~ ; pwd ; mkdir -p a/b ; cp -r src dst ; mv a b ; rm -r dossier
cat f ; head -n 20 f ; tail -n 20 f ; tail -f f ; wc -l f ; less f
ls -l f ; stat f ; chmod 600 f ; chmod +x s.sh ; sudo chown user:groupe f
ps aux ; pgrep -a nom ; kill PID ; kill -9 PID ; pkill -f motif ; htop
systemctl status svc ; sudo systemctl restart svc ; journalctl -u svc -f
df -h ; du -sh dossier ; free -h ; uname -a ; uptime
ip -br a ; ss -tlnp ; ping -c 4 h ; nc -zv h 443 ; dig +short h ; curl -s url
grep -rin motif . ; grep -c ERROR f ; sed -i 's/a/b/' f ; sort | uniq -c | sort -rn
find . -name "*.log" -size +10M -mtime +30
cmd > out 2>&1 ; cmd | tee out ; cmd1 && cmd2 ; echo $?
tar czf a.tar.gz dossier/ ; tar xzf a.tar.gz
```

```powershell
# ---------- PowerShell ----------
gci -Force ; cd ~ ; pwd ; New-Item -ItemType Directory a\b -Force ; Copy-Item src dst -Recurse ; Move-Item a b ; Remove-Item dossier -Recurse -WhatIf
gc f ; gc f -TotalCount 20 ; gc f -Tail 20 ; gc f -Tail 10 -Wait ; (gc f).Count ; gc f | more
Get-Acl f | fl ; icacls f ; icacls f /inheritance:r /grant:r "${env:USERNAME}:(R,W)"
gps ; gps -Name nom ; Stop-Process -Id PID ; Stop-Process -Id PID -Force ; taskkill /PID PID /T /F
Get-Service svc ; Restart-Service svc ; Get-WinEvent -LogName System -MaxEvents 20
Get-PSDrive -PSProvider FileSystem ; (gci dossier -Recurse -File | measure Length -Sum).Sum/1MB ; gcim Win32_OperatingSystem
Get-NetIPAddress -AddressFamily IPv4 ; Get-NetTCPConnection -State Listen ; Test-Connection h ; Test-NetConnection h -Port 443 ; Resolve-DnsName h ; irm url
gci -Recurse -File | sls motif ; (sls ERROR f).Count ; (gc f) -replace 'a','b' | Set-Content f ; Group-Object | sort Count -desc
gci -Recurse -Filter *.log | ? { $_.Length -gt 10MB -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
cmd *> out ; cmd | Tee-Object out ; cmd1; if ($?) { cmd2 } ; $? ; $LASTEXITCODE
Compress-Archive dossier a.zip ; Expand-Archive a.zip dest ; tar -czf a.tar.gz dossier
```

Pièges : alias PowerShell ≠ commandes Linux (`ls -la` ✗ → `gci -Force`) · `curl` = `Invoke-WebRequest` dans Windows PowerShell 5.1 (→ `curl.exe`) · encodage UTF-16 de `>` en 5.1 (→ `Out-File -Encoding utf8`) · Linux sensible à la casse, Windows non.
