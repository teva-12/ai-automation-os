#!/usr/bin/env bash
# Creates the owner user from OWNER_TELEGRAM_ID / OWNER_NAME and seeds default permissions.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
[[ "$OWNER_TELEGRAM_ID" =~ ^[0-9]+$ ]] || { echo "OWNER_TELEGRAM_ID must be numeric"; exit 1; }
SAFE_NAME=${OWNER_NAME//\'/\'\'}
docker compose exec -T -e PGPASSWORD="$AIOS_DB_PASSWORD" postgres \
  psql -v ON_ERROR_STOP=1 -U aios_app -d aios -q <<SQL
WITH u AS (
  INSERT INTO users (telegram_id, display_name, role)
  VALUES ($OWNER_TELEGRAM_ID, '$SAFE_NAME', 'owner')
  ON CONFLICT (telegram_id) DO UPDATE SET display_name = EXCLUDED.display_name
  RETURNING id
)
SELECT seed_user_defaults(id) FROM u;
INSERT INTO audit_logs (actor, action, target, status, workflow)
VALUES ('system','seed_owner','telegram_id:$OWNER_TELEGRAM_ID','success','phase1');
SQL
echo "owner seeded"
