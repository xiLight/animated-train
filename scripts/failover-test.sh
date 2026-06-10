#!/usr/bin/env bash
# Live-Test des Failovers:
#   1. zeigt den aktiven Knoten hinter HAProxy
#   2. killt mariadb1 hart (simulierter Crash)
#   3. prueft, dass HAProxy binnen Sekunden auf mariadb2 umschaltet
#   4. startet mariadb1 wieder und prueft den automatischen Failback
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

q() {
    docker compose exec -T haproxy mariadb -h127.0.0.1 -P3306 \
        -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --connect-timeout=2 -N -B -e "$1"
}

echo ">> Aktiver Knoten via HAProxy: $(q 'SELECT @@wsrep_node_name')"

echo ">> Kille mariadb1 (simulierter Crash) ..."
docker kill mariadb1 >/dev/null

echo ">> Warte auf Failover zu mariadb2 ..."
ok=0
for i in $(seq 1 30); do
    active=$(q 'SELECT @@wsrep_node_name' 2>/dev/null || true)
    if [ "$active" = "mariadb2" ]; then
        echo ">> Failover OK nach ~$((i * 2))s - aktiv: ${active}, Schreibtest:"
        q "CREATE TABLE IF NOT EXISTS ${MARIADB_DATABASE}.failover_test (ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP, node VARCHAR(64)); INSERT INTO ${MARIADB_DATABASE}.failover_test (node) VALUES (@@wsrep_node_name); SELECT * FROM ${MARIADB_DATABASE}.failover_test ORDER BY ts DESC LIMIT 1;"
        ok=1
        break
    fi
    sleep 2
done
[ "$ok" = "1" ] || { echo "!! Failover fehlgeschlagen - scripts/status.sh pruefen."; exit 1; }

echo ">> Starte mariadb1 wieder (Selbstheilung: IST/SST vom laufenden Knoten) ..."
docker start mariadb1 >/dev/null

echo ">> Warte auf Failback zu mariadb1 ..."
for i in $(seq 1 90); do
    active=$(q 'SELECT @@wsrep_node_name' 2>/dev/null || true)
    if [ "$active" = "mariadb1" ]; then
        echo ">> Failback OK nach ~$((i * 2))s - aktiv: ${active}"
        echo ">> Test erfolgreich abgeschlossen."
        exit 0
    fi
    sleep 2
done
echo "!! Failback nicht erfolgt - scripts/status.sh pruefen."
exit 1
