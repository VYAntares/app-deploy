#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# new-site.sh <nom-client> <domaine>
# Copie app-template vers /home/antares/app-deploy/apps/<nom-client>
# et lance init.sh pour configurer le domaine et générer les secrets.
#
# Usage :
#   ./new-site.sh test test.vyantares.ch
#   ./new-site.sh dupont dupont.ch
# ---------------------------------------------------------------------------

DEPLOY_DIR="/home/antares/app-deploy"
TEMPLATE_DIR="$DEPLOY_DIR/app-template"
APPS_DIR="$DEPLOY_DIR/apps"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <nom-client> <domaine>"
  echo "Exemple: $0 test test.vyantares.ch"
  exit 1
fi

CLIENT_NAME="$1"
DOMAIN="$2"
DEST_DIR="$APPS_DIR/$CLIENT_NAME"

mkdir -p "$APPS_DIR"

if [[ -d "$DEST_DIR" ]]; then
  echo "Erreur : $DEST_DIR existe déjà."
  exit 1
fi

echo "→ Copie du template vers $DEST_DIR (sans .git)..."
rsync -a --exclude='.git' "$TEMPLATE_DIR/" "$DEST_DIR/"

echo "→ Initialisation du projet..."
bash "$DEST_DIR/scripts/init.sh" "$CLIENT_NAME" "$DOMAIN"

echo ""
echo "Prochaine étape :"
echo "  cd $DEST_DIR && docker compose up -d"
