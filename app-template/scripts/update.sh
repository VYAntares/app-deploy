#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# update.sh
# Rebuilds and restarts the containers for THIS deployed app.
# Run from inside the deployed project (e.g. /home/antares/app-deploy/apps/<client>).
#
# Note : ce script ne pull pas de git — les apps déployées dans apps/ ne sont
# pas des dépôts git. Pour récupérer des améliorations du template,
# mets à jour /home/antares/app-deploy (git pull) puis re-synchronise
# manuellement les fichiers du template dans le dossier du client.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "→ Rebuild et redémarrage des containers..."
docker compose up -d --build --remove-orphans

echo "→ Nettoyage des images obsolètes..."
docker image prune -f

echo "✓ Mise à jour terminée."
docker compose ps
