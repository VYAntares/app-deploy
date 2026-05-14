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
POSTGRES_PASSWORD="$(openssl rand -hex 16)"

sed \
  -e "s/GENERATED/${JWT_SECRET}/" \
  -e "s/GENERATED/${POSTGRES_PASSWORD}/" \
  -e "s/CLIENT_NAME/${CLIENT_NAME}/g" \
  "$ROOT_DIR/.env.example" > "$ROOT_DIR/.env"

# DATABASE_URL has CLIENT_NAME already replaced but GENERATED still present — fix it
sed -i "s|postgresql://${CLIENT_NAME}:GENERATED@|postgresql://${CLIENT_NAME}:${POSTGRES_PASSWORD}@|g" "$ROOT_DIR/.env"

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
echo "  cd $(basename "$ROOT_DIR") && docker compose up -d"
