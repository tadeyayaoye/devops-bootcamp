# Cree un bac a sable d'exercices dans $HOME\bac-a-sable (Windows PowerShell 5.1 ou PowerShell 7).
# Relancable : il repart de zero.
#   powershell -ExecutionPolicy Bypass -File preparer-bac-a-sable.ps1
param([string]$Dossier = (Join-Path $HOME 'bac-a-sable'))
$ErrorActionPreference = 'Stop'

if (Test-Path $Dossier) { Remove-Item $Dossier -Recurse -Force }
$dirs = 'logs', 'data', 'scripts', 'config', 'archives', 'tmp',
        'docs\projets\alpha', 'docs\projets\beta', 'docs\projets\gamma'
foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $Dossier $d) -Force | Out-Null }
Set-Location $Dossier
$r = New-Object System.Random

# Journal applicatif de 500 lignes
$niveaux = 'INFO', 'INFO', 'INFO', 'INFO', 'WARN', 'ERROR', 'DEBUG'
$lignes = foreach ($i in 1..500) {
    '2026-10-28 {0:D2}:{1:D2}:{2:D2} {3,-5} [worker-{4}] traitement de la requete {5}' -f `
        ([int][math]::Floor($i / 60) % 24), ($i % 60), $r.Next(60), $niveaux[$r.Next($niveaux.Count)], $r.Next(4), $i
}
$lignes += '2026-10-28 23:59:59 ERROR [worker-1] connexion refusee a la base : password=NE_JAMAIS_LOGUER_UN_MOT_DE_PASSE'
$lignes | Set-Content -Path logs\app.log -Encoding UTF8

# Journal d'acces HTTP
$codes = 200, 200, 200, 200, 201, 404, 500
$acces = foreach ($i in 1..200) {
    '192.168.1.{0} - - [28/Oct/2026:10:{1:D2}:00] "GET /api/tasks/{2} HTTP/1.1" {3} {4}' -f `
        ($r.Next(20) + 1), ($i % 60), $r.Next(50), $codes[$r.Next($codes.Count)], $r.Next(5000)
}
$acces | Set-Content -Path logs\access.log -Encoding UTF8

# CSV de clients
$villes = 'Paris', 'Lyon', 'Lille', 'Nantes', 'Marseille', 'Bordeaux'
$csv = @('id;nom;ville;solde') + (1..30 | ForEach-Object { "$_;client$_;$($villes[$r.Next(6)]);$($r.Next(20000) - 5000)" })
$csv | Set-Content -Path data\clients.csv -Encoding UTF8

# Configuration et "secret"
@('# configuration de demo', 'port=8000', 'log_level=INFO', 'db_host=localhost', 'db_user=taskapi') |
    Set-Content -Path config\app.conf -Encoding UTF8
'jeton-secret-de-demo' | Set-Content -Path config\secret.txt -Encoding UTF8

# Scripts : un bonjour et une boucle infinie (exercice Stop-Process)
@('Write-Output "Bonjour $env:USERNAME, il est $(Get-Date -Format HH:mm)"') |
    Set-Content -Path scripts\bonjour.ps1 -Encoding UTF8
@('while ($true) { Write-Output "boucle $PID toujours en vie $(Get-Date -Format T)"; Start-Sleep -Seconds 5 }') |
    Set-Content -Path scripts\boucle.ps1 -Encoding UTF8

# Documents de tailles et dates variees
foreach ($p in 'alpha', 'beta', 'gamma') {
    foreach ($j in 1..3) { "Projet $p - document $j" | Set-Content -Path "docs\projets\$p\doc$j.txt" -Encoding UTF8 }
}
$octets = New-Object byte[] (30MB)
$r.NextBytes($octets)
[System.IO.File]::WriteAllBytes((Join-Path $Dossier 'docs\projets\beta\gros-fichier.bin'), $octets)
foreach ($f in 'doc1.txt', 'doc2.txt') { (Get-Item "docs\projets\alpha\$f").LastWriteTime = Get-Date '2025-01-15' }
$cache = New-Item -ItemType File -Path docs\.fichier-cache -Force
$cache.Attributes = 'Hidden'

Write-Output "OK : bac a sable pret dans $Dossier"
Get-ChildItem $Dossier -Force
