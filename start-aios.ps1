# start-aios.ps1  -  run this after every reboot / wake-up.
# From PowerShell:
#   cd D:\as_teva\ai-os-phase1\AI-Automation-OS
#   powershell -ExecutionPolicy Bypass -File .\start-aios.ps1
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

function Test-Docker { docker info *> $null; return ($LASTEXITCODE -eq 0) }

# 1) Make sure Docker Desktop is running
if (-not (Test-Docker)) {
    Write-Host "Starting Docker Desktop..."
    $dd = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) { Start-Process $dd } else { Write-Host "Open Docker Desktop manually." }
    for ($i = 0; $i -lt 60 -and -not (Test-Docker); $i++) { Start-Sleep -Seconds 5 }
}
if (-not (Test-Docker)) { Write-Host "Docker is not ready yet. Wait a minute and run this script again."; exit 1 }
Write-Host "Docker is ready."

# 2) Start the stack
$envText = Get-Content (Join-Path $PSScriptRoot ".env") -Raw
if ($envText -match '(?m)^NGROK_DOMAIN=\S+') {
    Write-Host "Using the permanent ngrok URL."
    docker compose -f docker-compose.yml -f docker-compose.ngrok.yml up -d | Out-Null
} else {
    Write-Host "Using the temporary Cloudflare tunnel (new URL each time)."
    docker compose --profile tunnel up -d | Out-Null
    & (Join-Path $PSScriptRoot "refresh-tunnel.ps1")
}

# 3) Wait for n8n locally
$ready = $false
for ($i = 0; $i -lt 40 -and -not $ready; $i++) {
    Start-Sleep -Seconds 3
    $r = curl.exe -s http://localhost:5678/healthz 2>$null
    if ($r -match 'ok') { $ready = $true }
}
Write-Host ""
docker compose ps
Write-Host ""
if ($ready) {
    Write-Host "n8n is READY: http://localhost:5678"
    Write-Host "Telegram re-registers by itself when n8n starts. If the bot stays silent, Unpublish then Publish AIOS-Main."
} else {
    Write-Host "n8n is not answering yet. Wait a minute, then open http://localhost:5678"
}
