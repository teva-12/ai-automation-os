#!/bin/bash
# Runs once, on first start with an empty data volume.
# Two databases, two least-privilege roles:
#   n8n  -> owned by n8n_user   (n8n's own metadata)
#   aios -> owned by aios_app   (application source of truth)
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
CREATE ROLE n8n_user LOGIN PASSWORD '${N8N_DB_PASSWORD}';
CREATE ROLE aios_app LOGIN PASSWORD '${AIOS_DB_PASSWORD}';
CREATE DATABASE n8n  OWNER n8n_user;
CREATE DATABASE aios OWNER aios_app;
REVOKE ALL ON DATABASE n8n  FROM PUBLIC;
REVOKE ALL ON DATABASE aios FROM PUBLIC;
SQL
echo "init: databases n8n and aios created"
