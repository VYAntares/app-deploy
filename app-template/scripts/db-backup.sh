#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# db-backup.sh
# Dumps the postgres container to /mnt/data/backups/<project>/
# Run from the project directory or pass PROJECT_NAME as env var.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Derive project name from directory name (set by init.sh via cp -r)
PROJECT_NAME="${PROJECT_NAME:-$(basename "$ROOT_DIR")}"

# Load DB credentials from .env
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ROOT_DIR/.env" | xargs)
fi

BACKUP_DIR="/mnt/data/backups/${PROJECT_NAME}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${PROJECT_NAME}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "→ Backing up ${POSTGRES_DB} to ${BACKUP_FILE}..."

docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "$BACKUP_FILE"

echo "✓ Backup complete: ${BACKUP_FILE}"

# Keep only the 30 most recent backups
ls -t "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | tail -n +31 | xargs -r rm --
