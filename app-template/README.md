# App Template — Guide complet

Template de déploiement pour un site client sur VPS Ubuntu avec Docker.  
Conçu pour être **éducatif** : chaque décision d'architecture est expliquée.

---

## Pour quel type de site ?

Ce template est conçu pour les **applications web avec backend et base de données** — pas pour les sites vitrines.

**Idéal pour :**
- Application avec authentification (login / JWT)
- Dashboard client avec données personnalisées
- API REST + frontend séparé
- Tout projet qui nécessite : utilisateurs → données → logique métier

**Exemples concrets :**
- CRM léger, outil de gestion interne
- Application SaaS simple (facturation, réservations, suivi de commandes)
- Espace client avec compte et historique

**Ce que ce template n'est PAS :**
- Un site vitrine / landing page sans backend → trop lourd pour un simple HTML/CSS statique
- Une app temps-réel (chat, notifications live) → nécessite des WebSockets, non configurés ici
- Un hébergement multi-tenant → ici chaque client a son propre stack isolé (1 client = 1 dossier = 1 base de données)

---

## Table des matières

1. [Architecture globale](#1-architecture-globale)
2. [Les réseaux Docker](#2-les-réseaux-docker)
3. [Le flux d'une requête](#3-le-flux-dune-requête)
4. [Caddy — le reverse proxy](#4-caddy--le-reverse-proxy)
5. [Nginx — le serveur web](#5-nginx--le-serveur-web)
6. [Le backend Node.js](#6-le-backend-nodejs)
7. [La base de données PostgreSQL](#7-la-base-de-données-postgresql)
8. [Adminer](#8-adminer)
9. [Structure du projet](#9-structure-du-projet)
10. [Variables d'environnement](#10-variables-denvironnement)
11. [Workflow complet — déployer un client](#11-workflow-complet--déployer-un-client)
12. [Scripts utilitaires](#12-scripts-utilitaires)
13. [Concepts clés expliqués](#13-concepts-clés-expliqués)
14. [Checklist avant de mettre en production](#14-checklist-avant-de-mettre-en-production)

---

## 1. Architecture globale

```
Internet
   │
   ▼
┌─────────────────────────────────────┐
│  Caddy  (port 80 + 443)             │  ← seul container exposé sur le VPS
│  SSL automatique via Let's Encrypt  │    gère les certificats HTTPS tout seul
│  lit les labels Docker des autres   │    pas de config manuelle
│  containers pour router le trafic   │
└──────────────┬──────────────────────┘
               │ réseau Docker "web" (partagé entre tous les projets)
               ▼
┌─────────────────────────────────────┐
│  Nginx  (port 80, interne)          │  ← sert les fichiers HTML/CSS/JS
│  - fichiers statiques (frontend)    │    proxifie /api/* vers le backend
│  - proxy /api/* → backend:3000      │
└──────────────┬──────────────────────┘
               │ réseau Docker "internal" (privé, propre à ce projet)
       ┌───────┴────────┐
       ▼                ▼
┌────────────┐   ┌─────────────────┐
│  Backend   │   │   PostgreSQL    │
│  Node.js   │──▶│   port 5432     │
│  port 3000 │   │   données       │
└────────────┘   │   persistantes  │
                 └─────────────────┘
                        ▲
               ┌────────┘
               │
         ┌───────────┐
         │  Adminer  │  ← interface web pour gérer la DB
         │  port 8080│    accessible sur adminer.tondomaine.ch
         └───────────┘
```

**Règle fondamentale :** aucun container n'expose de port directement sur l'hôte, sauf Caddy.  
Tout le trafic entre par Caddy, circule dans les réseaux Docker internes, et ne sort jamais.

---

## 2. Les réseaux Docker

Ce projet utilise **deux réseaux** Docker distincts.

### Réseau `web` — externe, partagé

```yaml
networks:
  web:
    external: true
```

- Créé **une seule fois** sur le VPS : `docker network create web`
- Partagé entre **tous les projets** et Caddy
- `external: true` signifie que Docker Compose ne le crée pas — il l'utilise
- Caddy doit être sur ce réseau pour atteindre nginx et adminer

### Réseau `internal` — privé, propre au projet

```yaml
networks:
  internal:
    driver: bridge
```

- Créé **automatiquement** par Docker Compose au premier `up`
- Visible uniquement par les containers de ce projet
- Nginx, backend, postgres et adminer communiquent ici
- Postgres n'est **jamais** joignable depuis internet

### Qui est sur quel réseau ?

| Container | `web` | `internal` |
|-----------|:-----:|:----------:|
| nginx     | ✓     | ✓          |
| backend   |       | ✓          |
| postgres  |       | ✓          |
| adminer   | ✓     | ✓          |

Backend et postgres sont **uniquement** sur `internal` — ils sont invisibles depuis Caddy.

---

## 3. Le flux d'une requête

### Requête vers le frontend (`https://dupont.ch`)

```
Navigateur
  → Caddy (HTTPS :443)
    → réseau "web"
      → nginx:80
        → sert /usr/share/nginx/html/index.html
```

### Requête vers l'API (`https://dupont.ch/api/auth/login`)

```
Navigateur
  → Caddy (HTTPS :443)
    → réseau "web"
      → nginx:80  (reçoit GET /api/auth/login)
        → proxy_pass http://backend:3000/   (devient GET /auth/login)
          → réseau "internal"
            → backend:3000
              → router Express
                → controller
                  → service
                    → postgres:5432
```

**Point important :** le préfixe `/api` est **strippé par nginx** avant d'atteindre le backend.  
Le backend ne voit que `/auth/login`, pas `/api/auth/login`.  
C'est la ligne `proxy_pass http://backend:3000/;` dans `nginx/default.conf` qui fait ça  
(le slash final après `3000` indique à nginx de remplacer `/api/` par `/`).

---

## 4. Caddy — le reverse proxy

Caddy est installé séparément sur le VPS (pas dans ce `docker-compose.yml`).  
Il tourne avec le plugin `caddy-docker-proxy` qui **lit les labels Docker** et se configure tout seul.

### Comment ça marche

Caddy scrute en permanence les labels des containers Docker actifs.  
Quand nginx démarre avec ces labels :

```yaml
labels:
  caddy: dupont.ch
  caddy.reverse_proxy: "{{upstreams 80}}"
  caddy_1: www.dupont.ch
  caddy_1.redir: "https://dupont.ch{uri} permanent"
```

Caddy génère automatiquement la config équivalente à :

```
dupont.ch {
  reverse_proxy nginx:80
}
www.dupont.ch {
  redir https://dupont.ch{uri} permanent
}
```

Et il obtient le certificat Let's Encrypt sans aucune intervention.  
`{{upstreams 80}}` est une macro de caddy-docker-proxy qui résout l'IP du container sur le port 80.

### Pourquoi Caddy et pas nginx comme reverse proxy ?

Caddy gère le SSL automatiquement. Avec nginx, il faudrait certbot + cron + config manuelle.  
Pour un multi-tenant (plusieurs clients sur le même VPS), Caddy est nettement plus simple.

---

## 5. Nginx — le serveur web

Nginx joue ici un rôle **interne** : il sert le frontend et proxifie l'API.  
Il ne gère pas le SSL (Caddy s'en charge).

### `nginx/default.conf`

```nginx
# Proxy les requêtes /api/* vers le backend
location /api/ {
    proxy_pass http://backend:3000/;   # ← le slash strip /api/
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
}

# Sert le frontend — fallback pour le routing SPA
location / {
    try_files $uri $uri/ /index.html;  # ← important pour les SPA (React, Vue)
}
```

`try_files $uri $uri/ /index.html` : si le fichier demandé n'existe pas sur le disque  
(ex: `/dashboard` dans une SPA), nginx renvoie `index.html` et laisse le JS gérer la route.

### Les volumes

```yaml
volumes:
  - ./nginx/default.conf:/etc/nginx/conf.d/default.conf  # config
  - ./frontend:/usr/share/nginx/html                      # fichiers servis
```

Modifier `frontend/` est visible **immédiatement** sans rebuild du container.

---

## 6. Le backend Node.js

### Architecture en couches

```
src/
├── index.js          ← démarre le serveur HTTP
├── app.js            ← configure Express (middlewares, routes, erreurs)
├── config/
│   └── index.js      ← charge et valide les variables d'environnement
├── db/
│   └── pool.js       ← connexion PostgreSQL (pool de connexions)
├── middleware/
│   ├── auth.js       ← vérifie le JWT sur les routes protégées
│   ├── rateLimit.js  ← limite le nombre de requêtes
│   └── validate.js   ← valide le body des requêtes
├── routes/
│   ├── index.js      ← monte toutes les routes sur le router principal
│   ├── health.js     ← GET /health — vérifie que l'API et la DB répondent
│   ├── auth.js       ← POST /auth/register  POST /auth/login
│   └── users.js      ← CRUD /users (routes protégées par JWT)
├── controllers/
│   ├── auth.controller.js    ← reçoit req, appelle le service, renvoie res
│   └── users.controller.js
└── services/
    ├── auth.service.js   ← logique métier : bcrypt, JWT
    └── mail.service.js   ← envoi d'emails via nodemailer
```

### Pourquoi séparer controllers et services ?

Le **controller** parle HTTP : il lit `req.body`, appelle le service, écrit `res.json()`.  
Le **service** parle métier : il ne sait pas qu'il y a une requête HTTP, juste des données.  
Cette séparation permet de réutiliser un service depuis plusieurs controllers,  
ou de le tester sans simuler une requête HTTP.

### Le pool de connexions PostgreSQL

```js
const pool = new Pool({ connectionString: config.db.url });
```

Un "pool" maintient plusieurs connexions ouvertes en permanence.  
Au lieu d'ouvrir/fermer une connexion à chaque requête (lent), le pool en réutilise une.  
`pg` gère ça automatiquement — `pool.query(...)` prend une connexion libre, l'utilise, la rend.

### Le middleware d'authentification JWT

```
POST /auth/login → reçoit email + password
  → vérifie en DB → si ok, génère un JWT signé avec JWT_SECRET
  → client reçoit le token et le stocke (localStorage)

GET /users → navigateur envoie : Authorization: Bearer <token>
  → middleware auth.js vérifie la signature → si ok, req.user = payload → route s'exécute
```

Le JWT contient `{ sub: userId, email }`. Il est **signé** (pas chiffré) — n'y mets pas de données sensibles.

### Le rate limiting

Deux niveaux :
- **Global** : 200 requêtes / 15 min par IP — protège l'API en général
- **Auth** : 20 requêtes / 15 min par IP sur `/auth/*` — empêche le brute force de mots de passe

### La validation (`middleware/validate.js`)

Validateur maison léger, sans dépendance. Usage :

```js
validate({
  email: { type: 'email', required: true },
  password: { type: 'string', required: true, minLength: 8 }
})
```

Renvoie un `422 Unprocessable Entity` avec la liste des erreurs si la validation échoue.  
Pour des projets plus complexes, remplace-le par `zod` ou `joi`.

---

## 7. La base de données PostgreSQL

```yaml
postgres:
  image: postgres:16-alpine
  env_file: .env
  volumes:
    - postgres_data:/var/lib/postgresql/data
```

### Persistance des données

Le volume `postgres_data` est géré par Docker, stocké sur le VPS dans :
```
/var/lib/docker/volumes/<projet>_postgres_data/_data/
```

Supprimer le container ne supprime **pas** les données.  
Pour tout effacer : `docker volume rm <projet>_postgres_data`

### Variables attendues par l'image postgres officielle

L'image `postgres:16-alpine` lit automatiquement ces vars depuis `.env` :
- `POSTGRES_DB` → nom de la base créée au premier démarrage
- `POSTGRES_USER` → utilisateur créé
- `POSTGRES_PASSWORD` → son mot de passe

### Table users — à créer manuellement

Le backend attend une table `users`. Crée-la via Adminer ou avec :

```sql
CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  name          VARCHAR(100),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ
);
```

> Pour automatiser ça, monte un fichier `.sql` dans `/docker-entrypoint-initdb.d/` —
> postgres l'exécute automatiquement à la création de la base.

---

## 8. Adminer

Interface web légère pour gérer PostgreSQL depuis un navigateur.  
Accessible sur `https://adminer.dupont.ch` après déploiement.

**Connexion :**
- Système : PostgreSQL
- Serveur : `postgres` (nom du container, résolu par Docker)
- Utilisateur / Mot de passe / Base : valeurs de ton `.env`

> En production, pense à le commenter dans `docker-compose.yml` si le projet est sensible,
> ou protège-le avec une authentification Caddy (`basicauth`).

---

## 9. Structure du projet

```
app-template/
├── docker-compose.yml        ← orchestration des containers
├── .env.example              ← template des variables (ne commit jamais .env)
├── README.md                 ← ce fichier
│
├── backend/
│   ├── Dockerfile            ← image Node.js (node:20-alpine)
│   ├── package.json          ← dépendances npm
│   └── src/                  ← code source (voir §6)
│
├── frontend/
│   ├── index.html            ← page principale
│   ├── css/style.css
│   └── js/app.js             ← appels API, gestion du token JWT
│
├── nginx/
│   └── default.conf          ← config nginx (proxy + SPA fallback)
│
└── scripts/
    ├── init.sh               ← initialise un nouveau client
    ├── update.sh             ← rebuild + relance les containers de l'app
    └── db-backup.sh          ← sauvegarde la base de données
```

---

## 10. Variables d'environnement

Fichier `.env` — **jamais commité dans git**.  
Généré automatiquement par `init.sh` depuis `.env.example`.

| Variable | Rôle | Exemple |
|---|---|---|
| `NODE_ENV` | Mode Express (`production` désactive les stack traces) | `production` |
| `PORT` | Port d'écoute du backend | `3000` |
| `JWT_SECRET` | Clé de signature des tokens (doit être longue et aléatoire) | *(généré)* |
| `JWT_EXPIRES_IN` | Durée de vie du token | `7d` |
| `POSTGRES_DB` | Nom de la base de données | `dupont` |
| `POSTGRES_USER` | Utilisateur PostgreSQL | `dupont` |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | *(généré)* |
| `DATABASE_URL` | URL de connexion complète pour `pg` | `postgresql://...` |
| `SMTP_HOST` | Serveur mail (optionnel) | `smtp.example.com` |
| `CONTACT_EMAIL` | Expéditeur des emails | `contact@dupont.ch` |

---

## 11. Workflow complet — déployer un client

### Pré-requis sur le VPS (une seule fois)

```bash
# 1. Créer le réseau partagé
docker network create web

# 2. Caddy avec caddy-docker-proxy doit tourner sur le réseau "web"
#    (voir la doc caddy-docker-proxy pour son docker-compose.yml)
```

### Déployer un nouveau client

```bash
# Sur le VPS, depuis /home/antares/app-deploy/
# new-site.sh copie le template dans apps/<client> et lance init.sh automatiquement
./new-site.sh dupont dupont.ch

# Pour un sous-domaine :
./new-site.sh test test.vyantares.ch

# Lancer les containers
cd /home/antares/app-deploy/apps/dupont
docker compose up -d

# Vérifier que tout tourne
docker compose ps
docker compose logs backend

# Vérifier que l'API répond (depuis le VPS)
curl https://dupont.ch/api/health
```

> **Pourquoi `new-site.sh` et pas `cp -r` ?**  
> Le repo `app-deploy` est versionné en git. `new-site.sh` utilise
> `rsync --exclude='.git'` pour copier uniquement les fichiers du template :
> chaque app déployée dans `apps/<client>` est ainsi indépendante,
> sans historique git du repo parent.

### Mettre à jour le backend

```bash
cd /home/antares/app-deploy/apps/dupont

# Modifier le code dans backend/src/
# puis rebuilder et relancer uniquement le backend :
docker compose up -d --build backend
```

### Mettre à jour le frontend

```bash
# Les fichiers frontend/ sont montés en volume — pas de rebuild
# Il suffit de modifier les fichiers :
nano frontend/index.html
# Le changement est visible immédiatement dans le navigateur
```

### Voir les logs

```bash
docker compose logs -f            # tous les containers
docker compose logs -f backend    # backend seulement
docker compose logs -f nginx      # nginx seulement
```

### Arrêter / Supprimer

```bash
docker compose down               # arrête et supprime les containers (données conservées)
docker compose down -v            # + supprime les volumes (⚠ données perdues)
```

---

## 12. Scripts utilitaires

### `scripts/init.sh <client-name> <domaine>`

À exécuter **une seule fois** après avoir copié le template.

Ce qu'il fait dans l'ordre :
1. Vérifie que les 2 arguments sont fournis
2. Remplace `CLIENT_DOMAIN` → vrai domaine dans `docker-compose.yml`
3. Remplace `CLIENT_NAME` → nom client dans `docker-compose.yml`
4. Génère un `.env` depuis `.env.example` avec :
   - `JWT_SECRET` aléatoire (`openssl rand -hex 32`)
   - `POSTGRES_PASSWORD` aléatoire (`openssl rand -hex 16`)
   - `DATABASE_URL` complète avec le bon mot de passe
5. Affiche un résumé et la commande pour lancer

### `scripts/update.sh`

Rebuild et relance les containers de l'app déployée.  
À exécuter depuis le dossier du projet (`apps/<client>`) après une modification
du backend ou du `docker-compose.yml`.

```bash
cd /home/antares/app-deploy/apps/dupont
./scripts/update.sh
```

> Ce script ne fait **pas** de `git pull` : les apps déployées dans `apps/`
> ne sont pas des dépôts git. Pour récupérer des améliorations du template,
> mets à jour `/home/antares/app-deploy` (`git pull`) puis re-synchronise
> manuellement les fichiers utiles dans le dossier du client.

### `scripts/db-backup.sh`

Sauvegarde la base avec `pg_dump`, compresse avec `gzip`,  
stocke dans `/mnt/data/backups/<projet>/` avec un timestamp.  
Conserve les **30 dernières sauvegardes** automatiquement.

```bash
# Depuis le dossier du projet :
./scripts/db-backup.sh

# Ou avec un nom explicite :
PROJECT_NAME=dupont ./scripts/db-backup.sh
```

Pour automatiser, ajoute un cron sur le VPS :

```bash
# Sauvegarde quotidienne à 2h du matin
0 2 * * * cd /home/antares/app-deploy/apps/dupont && ./scripts/db-backup.sh >> /var/log/backup-dupont.log 2>&1
```

---

## 13. Concepts clés expliqués

### JWT (JSON Web Token)

Un JWT est une chaîne en trois parties séparées par des points : `header.payload.signature`.  
Le serveur le génère à la connexion et le signe avec `JWT_SECRET`.  
Le client le stocke et l'envoie dans chaque requête : `Authorization: Bearer <token>`.  
Le serveur **vérifie la signature** sans consulter la base de données — c'est son avantage.  
Si quelqu'un modifie le payload, la signature ne correspond plus → token rejeté.

### bcrypt

bcrypt est un algorithme de hachage conçu pour être **lent** (intentionnellement).  
Les 12 "rounds" signifient que hacher un mot de passe prend ~250ms.  
C'est négligeable pour un utilisateur, mais rend le brute force prohibitif.  
On ne stocke **jamais** un mot de passe en clair, seulement son hash.

### Pool de connexions PostgreSQL

Ouvrir une connexion TCP à PostgreSQL prend ~20-50ms.  
Un pool maintient N connexions ouvertes permanentes.  
`pool.query()` en emprunte une, l'utilise, la rend — temps d'attente quasi nul.  
Par défaut `pg` utilise un pool de 10 connexions.

### Reverse proxy

Un reverse proxy reçoit les requêtes des clients et les transmet aux serveurs internes.  
Les clients ne voient que le proxy — les serveurs internes sont invisibles.  
Avantages : SSL centralisé, load balancing, rate limiting, logs centralisés.  
Ici : Caddy est le reverse proxy externe, nginx est un proxy interne.

### Variables d'environnement

Les variables d'environnement permettent de configurer une application sans modifier son code.  
C'est essentiel pour la sécurité (pas de secrets dans le code) et la portabilité  
(même image Docker, comportement différent selon l'environnement).  
Le fichier `.env` ne doit **jamais** être commité dans git — ajoute-le à `.gitignore`.

---

## 14. Checklist avant de mettre en production

- [ ] `./scripts/init.sh` a été exécuté (secrets générés, placeholders remplacés)
- [ ] `.env` existe et ne contient plus de placeholder `__JWT_SECRET__`, `__DB_PASSWORD__` ou `CLIENT_NAME`
- [ ] Le réseau Docker `web` existe : `docker network ls | grep web`
- [ ] Caddy tourne sur le réseau `web`
- [ ] Le DNS du domaine pointe vers l'IP du VPS
- [ ] La table `users` a été créée dans PostgreSQL
- [ ] `docker compose up -d` sans erreur
- [ ] `curl https://mondomaine.ch/api/health` répond `{"status":"ok","db":"ok"}`
- [ ] Adminer accessible sur `https://adminer.mondomaine.ch`
- [ ] Une sauvegarde automatique est en place (cron `db-backup.sh`)
- [ ] Le `.env` n'est pas dans git (`.gitignore` vérifié)
