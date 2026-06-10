#!/usr/bin/env bash
# Logisches Backup (mariadb-dump) vom ersten gesunden Knoten nach ./backups/.
# --single-transaction: konsistenter Snapshot ohne Tabellen-Locks.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups

node=""
for n in mariadb1 mariadb2; do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' "$n" 2>/dev/null)" = "healthy" ]; then
        node="$n"
        break
    fi
done
[ -n "$node" ] || { echo "!! Kein gesunder Knoten gefunden."; exit 1; }

out="backups/dump-$(date +%Y%m%d-%H%M%S).sql.gz"
echo ">> Dump von ${node} nach ${out} ..."
docker exec "$node" sh -c \
    'mariadb-dump --all-databases --single-transaction --quick --routines --triggers --events -uroot -p"$MARIADB_ROOT_PASSWORD"' \
    | gzip > "$out"
echo ">> Fertig: ${out} ($(du -h "$out" | cut -f1))"
