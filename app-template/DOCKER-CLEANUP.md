# Docker — Voir et supprimer proprement

## Voir tout

```bash
# Containers (actifs)
docker ps

# Containers (tous, y compris arrêtés)
docker ps -a

# Images
docker images

# Volumes (là où les données sont stockées)
docker volume ls

# Réseaux
docker network ls

# Résumé global avec taille disque
docker system df
```

---

## Où sont les données

```bash
# Répertoire racine Docker sur le VPS
docker info | grep "Docker Root Dir"
# → généralement /var/lib/docker

# Emplacement exact d'un volume (ex: test_postgres_data)
docker volume inspect test_postgres_data
# → champ "Mountpoint" = chemin physique sur le VPS

# Tous les volumes avec leur emplacement
docker volume ls -q | xargs -I{} docker volume inspect {} --format '{{.Name}} → {{.Mountpoint}}'
```

---

## Supprimer un projet complet (ex: test)

```bash
cd /home/antares/app-deploy/apps/test

# 1. Arrêter et supprimer les containers + réseau interne
docker compose down

# 2. Supprimer aussi les volumes (⚠ données perdues définitivement)
docker compose down -v

# 3. Supprimer l'image buildée
docker rmi test-backend

# 4. Supprimer les fichiers du projet
rm -rf /home/antares/app-deploy/apps/test
```

---

## Reset complet Docker — ne rien laisser

```bash
# Arrêter tous les containers actifs
docker stop $(docker ps -q)

# Supprimer tous les containers
docker rm $(docker ps -a -q)

# Supprimer toutes les images
docker rmi $(docker images -q)

# Supprimer tous les volumes (⚠ toutes les données DB perdues)
docker volume rm $(docker volume ls -q)

# Supprimer tous les réseaux créés manuellement
docker network prune

# OU — une seule commande qui fait tout
docker system prune -a --volumes
```

---

## Vérifier qu'il ne reste rien

```bash
docker ps -a       # → aucun container
docker images      # → aucune image
docker volume ls   # → aucun volume
docker network ls  # → seulement bridge, host, none (les 3 défauts Docker)
ls /var/lib/docker/volumes/   # → vide
```

---

## Emplacements physiques sur le VPS

| Ce qui est stocké | Emplacement |
|---|---|
| Données Docker (tout) | `/var/lib/docker/` |
| Volumes nommés (DB) | `/var/lib/docker/volumes/` |
| Images | `/var/lib/docker/image/` |
| Fichiers projet | `/home/antares/app-deploy/apps/<client>/` |
| Certificats Caddy | Dans le volume du container Caddy |
