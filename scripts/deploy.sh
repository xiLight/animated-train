#!/usr/bin/env bash
# Erst-Deployment / Update des Clusters. Idempotent - kann jederzeit erneut
# ausgefuehrt werden. Legt beim ersten Lauf eine .env mit Zufallspasswoertern an.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo ">> Keine .env gefunden - erzeuge eine mit zufaelligen Passwoertern."
    cat > .env <<EOF
MARIADB_ROOT_PASSWORD=$(openssl rand -hex 16)
MARIADB_DATABASE=appdb
MARIADB_USER=app
MARIADB_PASSWORD=$(openssl rand -hex 16)
GALERA_SST_PASSWORD=$(openssl rand -hex 16)
GALERA_CLUSTER_NAME=mariadb-cluster
GALERA_GCACHE_SIZE=512M
INNODB_BUFFER_POOL_SIZE=256M
DB_PORT=3306
STATS_PORT=8404
EOF
    chmod 600 .env
    echo ">> .env angelegt - Zugangsdaten stehen dort."
fi

echo ">> Baue Images (haproxy, garbd) ..."
docker compose build --quiet

echo ">> Starte Cluster ..."
docker compose up -d

echo ">> Warte auf gesunde Datenbank-Knoten (Erst-Sync kann etwas dauern) ..."
for i in $(seq 1 60); do
    h1=$(docker inspect -f '{{.State.Health.Status}}' mariadb1 2>/dev/null || echo "n/a")
    h2=$(docker inspect -f '{{.State.Health.Status}}' mariadb2 2>/dev/null || echo "n/a")
    printf '\r   mariadb1: %-12s mariadb2: %-12s (%3ds)' "$h1" "$h2" $((i * 5))
    if [ "$h1" = "healthy" ] && [ "$h2" = "healthy" ]; then
        echo
        break
    fi
    sleep 5
done
echo

./scripts/status.sh
echo
echo ">> Fertig."
echo "   Datenbank-Endpunkt:  <host>:${DB_PORT:-3306}  (via HAProxy, automatisches Failover)"
echo "   HAProxy-Statusseite: http://<host>:${STATS_PORT:-8404}"
