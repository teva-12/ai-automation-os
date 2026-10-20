# refresh-tunnel.ps1
# Restarts the Cloudflare quick tunnel, writes the NEW public URL into .env, and restarts n8n.
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File .\refresh-tunnel.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

docker compose --profile tunnel up -d cloudflared | Out-Null
docker compose --profile tunnel restart cloudflared | Out-Null

# The real tunnel URL is the random-name one; cloudflared also logs https://api.trycloudflare.com, which we must ignore.
$pattern = 'https://(?!api\.)[a-z0-9-]+\.trycloudflare\.com'
$url = $null
for ($i = 0; $i -lt 30 -and -not $url; $i++) {
    Start-Sleep -Seconds 2
    $logs = docker compose --profile tunnel logs --since 2m cloudflared 2>&1 | Out-String
    $m = [regex]::Matches($logs, $pattern)
    if ($m.Count -gt 0) { $url = $m[$m.Count - 1].Value }
}
if (-not $url) { Write-Host "No tunnel URL yet. Wait a minute and run the script again."; exit 1 }

$envPath = Join-Path $PSScriptRoot ".env"
$content = Get-Content $envPath -Raw
$content = [regex]::Replace($content, 'https://[a-z0-9-]+\.trycloudflare\.com', $url)
Set-Content -Path $envPath -Value $content -NoNewline -Encoding ascii

docker compose up -d n8n | Out-Null
Write-Host ""
Write-Host "New tunnel URL: $url"

# Wait until n8n answers through the public URL (up to ~2 minutes)
$ok = $false
for ($i = 0; $i -lt 40 -and -not $ok; $i++) {
    Start-Sleep -Seconds 3
    $resp = curl.exe -s "$url/healthz" 2>$null
    if ($resp -match 'ok') { $ok = $true }
}
if ($ok) { Write-Host "Public URL is reachable. Now in n8n: Unpublish then Publish the AIOS-Main workflow." }
else { Write-Host "Public URL did not answer yet. Wait a minute, then run:  curl.exe -s $url/healthz" }
