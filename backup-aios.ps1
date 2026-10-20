# backup-aios.ps1 - saves both databases (your data + n8n workflows/credentials) to .\backups\<date>
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File .\backup-aios.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$lines = Get-Content (Join-Path $PSScriptRoot ".env")
function Get-EnvValue([string]$name) {
    $l = $lines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
    if (-not $l) { return "" }
    return ($l.Substring($name.Length + 1)).Trim()
}
$admin = Get-EnvValue "POSTGRES_ADMIN_USER"
$pw    = Get-EnvValue "POSTGRES_ADMIN_PASSWORD"
$keep  = 14
$k = Get-EnvValue "BACKUP_RETENTION_DAYS"
if ($k -match '^\d+$') { $keep = [int]$k }

$stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$dir = Join-Path $PSScriptRoot "backups\$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

try {
    foreach ($db in @("aios", "n8n")) {
        docker compose exec -T -e "PGPASSWORD=$pw" postgres pg_dump -U $admin -Fc -f "/tmp/$db.dump" $db
        if ($LASTEXITCODE -ne 0) { throw "pg_dump failed for $db" }
        docker compose cp "postgres:/tmp/$db.dump" (Join-Path $dir "$db.dump")
        if ($LASTEXITCODE -ne 0) { throw "copy failed for $db" }
        docker compose exec -T postgres rm -f "/tmp/$db.dump" | Out-Null
    }
}
finally { Remove-Variable pw -ErrorAction SilentlyContinue }

Get-ChildItem $dir | ForEach-Object { Write-Host ("{0}  {1:N0} KB" -f $_.Name, ($_.Length / 1KB)) }

# delete old backups
Get-ChildItem (Join-Path $PSScriptRoot "backups") -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$keep) } | Remove-Item -Recurse -Force

Write-Host ""
Write-Host "Backup saved in: $dir"
Write-Host "IMPORTANT: copy the backups folder off this PC (Drive / USB), and keep N8N_ENCRYPTION_KEY from .env somewhere safe, separate from the backups."
