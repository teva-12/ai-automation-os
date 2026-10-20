#!/usr/bin/env bash
# Backs up: both Postgres DBs, n8n workflows, n8n credentials (still encrypted).
# Usage: ./scripts/backup.sh      Cron: 0 4 * * *  /path/to/ai-os/scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
TS=$(date +%Y%m%d-%H%M%S); OUT="backups/$TS"; mkdir -p "$OUT"

for db in aios n8n; do
  docker compose exec -T -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" postgres \
    pg_dump -U "$POSTGRES_ADMIN_USER" -Fc "$db" > "$OUT/$db.dump"
done

# n8n exports (credentials stay encrypted with N8N_ENCRYPTION_KEY)
docker compose exec -T n8n sh -c 'rm -rf /backup/n8n-export/* && \
  n8n export:workflow --all --separate --output=/backup/n8n-export/workflows/ && \
  n8n export:credentials --all --separate --output=/backup/n8n-export/credentials/'
cp -r backups/n8n-export "$OUT/n8n-export"

chmod -R go-rwx "$OUT"
find backups -maxdepth 1 -type d -name '20*' -mtime +"${BACKUP_RETENTION_DAYS:-14}" -exec rm -rf {} +
echo "backup written to $OUT  (copy it OFF this machine, and store N8N_ENCRYPTION_KEY separately)"
