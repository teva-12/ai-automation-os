#!/usr/bin/env bash
# Applies postgres/migrations/*.sql in order, once each, inside a transaction.
# Safe to re-run. Usage: ./scripts/migrate.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
PSQL=(docker compose exec -T -e PGPASSWORD="$AIOS_DB_PASSWORD" postgres psql -v ON_ERROR_STOP=1 -U aios_app -d aios -q)

"${PSQL[@]}" -c "CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"

for f in postgres/migrations/*.sql; do
  v=$(basename "$f")
  done_already=$("${PSQL[@]}" -tA -c "SELECT 1 FROM schema_migrations WHERE version='$v'")
  if [[ "$done_already" == "1" ]]; then echo "skip   $v"; continue; fi
  echo "apply  $v"
  { echo "BEGIN;"; cat "$f"; echo "INSERT INTO schema_migrations(version) VALUES ('$v');"; echo "COMMIT;"; } | "${PSQL[@]}"
done
echo "migrations complete"
