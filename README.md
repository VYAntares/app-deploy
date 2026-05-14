# app-deploy

Infrastructure de déploiement multi-clients sur VPS Ubuntu avec Docker.  
Un seul VPS, plusieurs sites, chacun isolé dans son propre stack.

---

## Vue d'ensemble

```
Internet
   │
   ▼
┌─────────────────────────────────────┐
│  Caddy  (port 80 + 443)             │  ← un seul container exposé sur le VPS
│  SSL automatique via Let's Encrypt  │    lit les labels Docker pour router
└──────────────┬──────────────────────┘
               │ réseau Docker "web" (partagé)
       ┌───────┴───────┬──────────────────┐
       ▼               ▼                  ▼
 apps/dupont/    apps/martin/       apps/test/
 nginx+backend   nginx+backend      nginx+backend
 +postgres       +postgres          +postgres
```

**Règle fondamentale :** Caddy est le seul point d'entrée. Chaque client a son
propre stack Docker isolé. Ajouter un client = 1 commande.

---

## Structure du repo

```
app-deploy/
├── new-site.sh          ← crée un nouveau client (commande principale)
├── caddy/
│   └── docker-compose.yml   ← reverse proxy Caddy (lancé une seule fois)
├── app-template/        ← template copié pour chaque nouveau client
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── backend/         ← API Node.js (Express + PostgreSQL + JWT)
│   ├── frontend/        ← HTML/CSS/JS statique servi par nginx
│   ├── nginx/           ← config nginx (proxy /api/* + SPA fallback)
│   └── scripts/
│       ├── init.sh      ← appelé par new-site.sh, génère les secrets
│       ├── update.sh    ← rebuild + relance les containers du client
│       └── db-backup.sh ← dump PostgreSQL compressé avec rotation 30j
└── apps/                ← sites déployés (ignoré par git — secrets)
    ├── dupont/
    ├── martin/
    └── ...
```

---

## 1. Installation du VPS (une seule fois)

### Prérequis

```bash
# Docker + Docker Compose doivent être installés
docker --version
docker compose version

# Créer le réseau partagé entre Caddy et tous les projets
docker network create web
```

### Lancer Caddy

```bash
cd /home/antares/app-deploy/caddy
docker compose up -d

# Vérifier
docker ps | grep caddy
```

Caddy démarre, écoute sur les ports 80 et 443, et surveille en permanence
les labels Docker des autres containers pour router le trafic automatiquement.

---

## 2. Déployer un nouveau client

```bash
cd /home/antares/app-deploy

# Usage : ./new-site.sh <nom-client> <domaine>
./new-site.sh dupont dupont.ch
./new-site.sh martin app.martin.ch
./new-site.sh test test.vyantares.ch
```

Ce que fait `new-site.sh` en coulisses :

1. Copie `app-template/` vers `apps/<client>/` via `rsync --exclude='.git'`
2. Appelle `scripts/init.sh` qui :
   - Remplace les placeholders `CLIENT_DOMAIN` et `CLIENT_NAME` dans `docker-compose.yml`
   - Génère un `.env` avec des secrets aléatoires (`JWT_SECRET`, `POSTGRES_PASSWORD`)
3. Affiche un résumé et la commande pour lancer

### Lancer le site

```bash
cd /home/antares/app-deploy/apps/dupont
docker compose up -d

# Vérifier que tout tourne
docker compose ps
docker compose logs backend

# Vérifier que l'API répond
curl https://dupont.ch/api/health
```

### Créer la table users dans PostgreSQL

Le backend attend une table `users`. Crée-la via Adminer
(`https://adminer.dupont.ch`) ou directement :

```bash
docker compose exec postgres psql -U dupont -d dupont -c "
CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name          VARCHAR(100),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ
);"
```

---

## 3. Opérations courantes

### Voir les logs

```bash
cd /home/antares/app-deploy/apps/dupont

docker compose logs -f              # tous les containers
docker compose logs -f backend      # backend seulement
docker compose logs -f nginx        # nginx seulement
```

### Mettre à jour le backend

```bash
cd /home/antares/app-deploy/apps/dupont

# Modifier les fichiers dans backend/src/
# puis :
./scripts/update.sh
# → rebuild l'image + relance les containers + prune les vieilles images
```

### Mettre à jour le frontend

Les fichiers `frontend/` sont montés en volume — pas de rebuild.  
La modification est visible **immédiatement** dans le navigateur.

```bash
nano /home/antares/app-deploy/apps/dupont/frontend/index.html
```

### Sauvegarder la base de données

```bash
cd /home/antares/app-deploy/apps/dupont
./scripts/db-backup.sh
# → /mnt/data/backups/dupont/dupont_20240101_020000.sql.gz
```

Les 30 dernières sauvegardes sont conservées automatiquement.

Pour automatiser avec cron :

```bash
crontab -e
# Ajouter :
0 2 * * * cd /home/antares/app-deploy/apps/dupont && ./scripts/db-backup.sh >> /var/log/backup-dupont.log 2>&1
```

### Arrêter / Supprimer un client

```bash
cd /home/antares/app-deploy/apps/dupont

docker compose down          # arrête (données conservées)
docker compose down -v       # + supprime les volumes (données perdues)

# Supprimer complètement le projet
rm -rf /home/antares/app-deploy/apps/dupont
```

---

## 4. Architecture réseau

Chaque client utilise deux réseaux Docker :

| Réseau | Portée | Qui l'utilise |
|--------|--------|---------------|
| `web` | Partagé entre tous les projets | Caddy ↔ nginx, Caddy ↔ adminer |
| `internal` | Privé au projet | nginx ↔ backend ↔ postgres ↔ adminer |

Le backend et postgres ne sont **jamais** joignables depuis Caddy ou internet.  
Seul nginx est sur les deux réseaux.

---

## 5. Mettre à jour le template

Les apps déployées dans `apps/` ne sont pas des dépôts git — elles ne
reçoivent pas les mises à jour du template automatiquement.

Pour récupérer une amélioration du template dans un client existant :

```bash
# 1. Mettre à jour le repo
cd /home/antares/app-deploy
git pull

# 2. Synchroniser manuellement le(s) fichier(s) modifié(s)
cp app-template/backend/src/middleware/rateLimit.js apps/dupont/backend/src/middleware/

# 3. Rebuilder
cd apps/dupont && ./scripts/update.sh
```

---

## 6. Checklist déploiement production

- [ ] `docker network create web` effectué
- [ ] Caddy tourne sur le réseau `web` : `docker ps | grep caddy`
- [ ] DNS du domaine pointe vers l'IP du VPS
- [ ] `./new-site.sh <client> <domaine>` exécuté sans erreur
- [ ] `.env` généré et ne contient plus de placeholder
- [ ] `docker compose up -d` sans erreur
- [ ] Table `users` créée dans PostgreSQL
- [ ] `curl https://<domaine>/api/health` répond `{"status":"ok","db":"ok"}`
- [ ] Adminer accessible sur `https://adminer.<domaine>`
- [ ] Sauvegarde automatique configurée (cron `db-backup.sh`)

---

## Référence

| Fichier | Rôle |
|---|---|
| `new-site.sh` | Crée un nouveau client à partir du template |
| `caddy/docker-compose.yml` | Lance le reverse proxy Caddy |
| `app-template/README.md` | Documentation détaillée du stack (backend, nginx, Caddy, JWT, etc.) |
| `app-template/DOCKER-CLEANUP.md` | Commandes Docker pour inspecter et nettoyer |
