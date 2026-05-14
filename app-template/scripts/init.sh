#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# init.sh <client-name> <domain>
# Initializes a client project from the template.
# Must be run from inside the copied project directory.
# ---------------------------------------------------------------------------

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <client-name> <domain>"
  echo "Example: $0 dupont dupont.ch"
  exit 1
fi

CLIENT_NAME="$1"
DOMAIN="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "→ Configuring docker-compose.yml..."
sed -i "s/CLIENT_DOMAIN/${DOMAIN}/g" "$ROOT_DIR/docker-compose.yml"
sed -i "s/CLIENT_NAME/${CLIENT_NAME}/g" "$ROOT_DIR/docker-compose.yml"

echo "→ Generating .env..."
JWT_SECRET="$(openssl rand -hex 32)"
DB_PASSWORD="$(openssl rand -hex 16)"

cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
sed -i "s|__JWT_SECRET__|${JWT_SECRET}|g" "$ROOT_DIR/.env"
sed -i "s|__DB_PASSWORD__|${DB_PASSWORD}|g" "$ROOT_DIR/.env"
sed -i "s/CLIENT_NAME/${CLIENT_NAME}/g" "$ROOT_DIR/.env"

chmod 600 "$ROOT_DIR/.env"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Client : ${CLIENT_NAME}"
echo "  Domain : https://${DOMAIN}"
echo "  Adminer: https://adminer.${DOMAIN}"
echo "  DB user: ${CLIENT_NAME}"
echo "  .env   : ${ROOT_DIR}/.env"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next step:"
echo "  cd ${ROOT_DIR} && docker compose up -d"
