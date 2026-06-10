#!/usr/bin/env bash
# Desaster-Wiederherstellung: nur noetig, wenn der KOMPLETTE Cluster hart
# gestorben ist (beide Knoten gecrasht) und nicht von alleine wieder hochkommt.
# Findet den Knoten mit dem neuesten Datenstand (hoechste Galera-seqno) und
# bootstrappt den Cluster von dort - der andere Knoten synct sich automatisch.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=mariadb-cluster
IMAGE=mariadb:11.4

echo ">> Stoppe alle Cluster-Dienste ..."
docker compose stop haproxy garbd mariadb1 mariadb2

# Liest die letzte Transaktions-Position (seqno) eines gestoppten Knotens.
# Bei unsauberem Stopp steht in grastate.dat -1, dann wird die Position
# per --wsrep-recover aus den InnoDB-Logs rekonstruiert.
seqno_of() {
    docker run --rm -v "${PROJECT}_$1_data:/var/lib/mysql" "$IMAGE" bash -c '
        s=$(grep -oP "^seqno:\s*\K-?\d+" /var/lib/mysql/grastate.dat 2>/dev/null || echo "")
        if [ -z "$s" ] || [ "$s" = "-1" ]; then
            s=$(mariadbd --user=mysql --wsrep-on=ON \
                --wsrep-provider=/usr/lib/galera/libgalera_smm.so \
                --wsrep-recover --log-error=/dev/stderr 2>&1 \
                | grep -oP "Recovered position:.*:\K-?\d+" | tail -1)
        fi
        echo "${s:--1}"' 2>/dev/null | tail -1
}

echo ">> Ermittle letzten Datenstand beider Knoten ..."
s1=$(seqno_of mariadb1)
s2=$(seqno_of mariadb2)
echo "   mariadb1: seqno=${s1}"
echo "   mariadb2: seqno=${s2}"

if [ "$s2" -gt "$s1" ]; then
    node=mariadb2; flag=FORCE_BOOTSTRAP_NODE2
else
    node=mariadb1; flag=FORCE_BOOTSTRAP_NODE1
fi
echo ">> Aktuellster Knoten: ${node} - bootstrappe von dort."

env "${flag}=1" docker compose up -d "$node"
echo ">> Warte bis ${node} gesund ist ..."
for i in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$node")" = "healthy" ] && break
    sleep 5
done

echo ">> Starte restliche Dienste (zweiter Knoten synct sich nun automatisch) ..."
env "${flag}=1" docker compose up -d
echo ">> Warte bis beide Knoten gesund sind ..."
for i in $(seq 1 120); do
    h1=$(docker inspect -f '{{.State.Health.Status}}' mariadb1 2>/dev/null || echo "n/a")
    h2=$(docker inspect -f '{{.State.Health.Status}}' mariadb2 2>/dev/null || echo "n/a")
    [ "$h1" = "healthy" ] && [ "$h2" = "healthy" ] && break
    sleep 5
done

# Force-Flag wieder entfernen: der Bootstrap-Knoten wird einmal neu erstellt
# und tritt dem (jetzt laufenden) Cluster ganz normal wieder bei. HAProxy
# faengt den kurzen Wechsel ab.
echo ">> Raeume Bootstrap-Flag auf (${node} wird einmal neu erstellt) ..."
docker compose up -d

./scripts/status.sh
echo ">> Wiederherstellung abgeschlossen."
