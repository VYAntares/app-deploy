#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "→ Pull des dernières modifications..."
git pull origin main

echo "→ Rebuild et redémarrage des containers..."
docker compose up -d --build --remove-orphans

echo "→ Nettoyage des images obsolètes..."
docker image prune -f

echo "✓ Mise à jour terminée."
docker compose ps
