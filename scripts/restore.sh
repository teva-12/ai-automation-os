#!/usr/bin/env bash
# DESTRUCTIVE: replaces aios + n8n databases with a backup.
# Usage: ./scripts/restore.sh backups/20261016-040000
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=${1:?usage: restore.sh <backup-dir>}
set -a; source .env; set +a
read -rp "This OVERWRITES current data from $DIR. Type RESTORE to continue: " ok
[[ "$ok" == "RESTORE" ]] || { echo aborted; exit 1; }

docker compose stop n8n
for db in aios n8n; do
  docker compose exec -T -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" postgres \
    pg_restore -U "$POSTGRES_ADMIN_USER" -d "$db" --clean --if-exists --no-owner --role="$( [ $db = aios ] && echo aios_app || echo n8n_user )" < "$DIR/$db.dump"
done
docker compose start n8n
echo "restored. N8N_ENCRYPTION_KEY in .env must match the one used when the backup was taken."
