# Applies postgres\migrations\*.sql in order, once each. Safe to re-run.
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File .\migrate.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$line = Get-Content .env | Where-Object { $_ -match '^AIOS_DB_PASSWORD=' } | Select-Object -First 1
if (-not $line) { throw "AIOS_DB_PASSWORD not found in .env" }
$password = $line.Substring('AIOS_DB_PASSWORD='.Length).Trim()

function Invoke-AiosPsql {
    param([string[]]$PsqlArgs)
    docker compose exec -T -e "PGPASSWORD=$password" postgres psql -X -v ON_ERROR_STOP=1 -U aios_app -d aios @PsqlArgs
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL command failed. Stopping safely." }
}

try {
    Invoke-AiosPsql -PsqlArgs @("-c", "CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());")

    $files = Get-ChildItem ".\postgres\migrations" -Filter "*.sql" | Sort-Object Name
    if (-not $files) { throw "No migration files found." }

    foreach ($file in $files) {
        $version = $file.Name
        $check = docker compose exec -T -e "PGPASSWORD=$password" postgres psql -X -A -t -v ON_ERROR_STOP=1 -U aios_app -d aios -c "SELECT 1 FROM schema_migrations WHERE version='$version';"
        if ($LASTEXITCODE -ne 0) { throw "Could not check migration status: $version" }
        if ($check -match '1') { Write-Host "SKIP:  $version already applied"; continue }

        Write-Host "APPLY: $version"
        # --single-transaction: if anything fails, nothing from this file is kept and it is not recorded.
        Invoke-AiosPsql -PsqlArgs @("--single-transaction", "-f", "/migrations/$version", "-c", "INSERT INTO schema_migrations(version) VALUES ('$version');")
        Write-Host "OK:    $version"
    }
    Write-Host "`nMigrations complete."
}
finally {
    Remove-Variable password, line -ErrorAction SilentlyContinue
}
