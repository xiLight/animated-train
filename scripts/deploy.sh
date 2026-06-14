#!/usr/bin/env bash
# Erst-Deployment / Update des Clusters.
# Kann jederzeit erneut ausgefuehrt werden.
#
# Portolan-Integration (optional):
#   Ist "portolan" im PATH, werden Subnet und Ports automatisch allokiert,
#   registriert und in die .env geschrieben. Alte Registrierungen werden
#   vorher freigegeben. Ohne portolan: Werte aus .env oder Defaults.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE_NAME="mariadb-cluster"
NET_NAME="${SERVICE_NAME}_db_cluster"

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

# Berechnet eine IP-Adresse aus einem /24-Subnet und einem Offset.
#   calc_ip "172.20.5.0/24" 10  -->  172.20.5.10
calc_ip() {
    local base="${1%/*}"        # 172.20.5.0
    local prefix="${base%.*}"   # 172.20.5
    echo "${prefix}.${2}"
}

# Liest eine Variable aus der .env (falls vorhanden).
env_val() {
    grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2-
}

# Setzt oder aktualisiert eine Variable in der .env.
env_set() {
    local var="$1" val="$2"
    if [ -f .env ] && grep -q "^${var}=" .env; then
        sed -i "s|^${var}=.*|${var}=${val}|" .env
    else
        echo "${var}=${val}" >> .env
    fi
}

# ---------------------------------------------------------------------------
# Portolan-Integration
# ---------------------------------------------------------------------------

USE_PORTOLAN=0
if command -v portolan &>/dev/null; then
    USE_PORTOLAN=1
    echo ">> Portolan erkannt - allokiere Netzwerk-Ressourcen automatisch."
fi

if [ "$USE_PORTOLAN" = "1" ]; then
    # --- Alte Registrierungen freigeben ---
    if [ -f .env ]; then
        old_db=$(env_val DB_PORT)
        old_stats=$(env_val STATS_PORT)
        [ -n "$old_db" ]    && portolan free "$old_db" 2>/dev/null || true
        [ -n "$old_stats" ] && portolan free "$old_stats" 2>/dev/null || true
        portolan rm-net "$NET_NAME" 2>/dev/null || true
        echo "   Alte Portolan-Registrierungen freigegeben."
    fi

    # --- Freies Subnet holen ---
    SUBNET=$(portolan next-subnet)
    if [ -z "$SUBNET" ]; then
        echo "!! portolan next-subnet lieferte kein Ergebnis." >&2
        echo "   Pruefe ob ein Subnet-Pool definiert ist (portolan pools)." >&2
        echo "   Fahre mit Default-Werten fort." >&2
        USE_PORTOLAN=0
    fi
fi

if [ "$USE_PORTOLAN" = "1" ]; then
    # --- IPs aus Subnet berechnen ---
    OFFSET_HAPROXY="${IP_OFFSET_HAPROXY:-10}"
    OFFSET_MARIADB1="${IP_OFFSET_MARIADB1:-11}"
    OFFSET_MARIADB2="${IP_OFFSET_MARIADB2:-12}"
    OFFSET_GARBD="${IP_OFFSET_GARBD:-13}"

    # Gateway ist immer .1 im /24-Netz
    GATEWAY="$(calc_ip "$SUBNET" 1)"
    IP_HAPROXY="$(calc_ip "$SUBNET" "$OFFSET_HAPROXY")"
    IP_MARIADB1="$(calc_ip "$SUBNET" "$OFFSET_MARIADB1")"
    IP_MARIADB2="$(calc_ip "$SUBNET" "$OFFSET_MARIADB2")"
    IP_GARBD="$(calc_ip "$SUBNET" "$OFFSET_GARBD")"

    # --- Freie Ports holen ---
    # Bevorzuge die Default-Ports, weiche bei Kollision automatisch aus.
    PREFERRED_DB="${DB_PORT_PREFER:-3306}"
    PREFERRED_STATS="${STATS_PORT_PREFER:-8404}"

    DB_PORT=$(portolan next-ports 1 "$PREFERRED_DB")
    portolan reserve "$DB_PORT" "$SERVICE_NAME" "MariaDB (via HAProxy)" 2>/dev/null
    STATS_PORT=$(portolan next-ports 1 "$PREFERRED_STATS")
    portolan reserve "$STATS_PORT" "$SERVICE_NAME" "HAProxy Stats" 2>/dev/null

    # --- Subnet bei Portolan registrieren ---
    portolan add-net "$NET_NAME" "$SUBNET" "$SERVICE_NAME" 2>/dev/null || true

    # --- Werte in .env schreiben ---
    # Falls .env noch nicht existiert, wird sie weiter unten angelegt;
    # hier aktualisieren wir nur die Netzwerk-Variablen einer bestehenden .env.
    if [ -f .env ]; then
        env_set SUBNET      "$SUBNET"
        env_set GATEWAY     "$GATEWAY"
        env_set IP_HAPROXY  "$IP_HAPROXY"
        env_set IP_MARIADB1 "$IP_MARIADB1"
        env_set IP_MARIADB2 "$IP_MARIADB2"
        env_set IP_GARBD    "$IP_GARBD"
        env_set DB_PORT     "$DB_PORT"
        env_set STATS_PORT  "$STATS_PORT"
    fi

    echo "   Subnet:     ${SUBNET}"
    echo "   Gateway:    ${GATEWAY}"
    echo "   HAProxy:    ${IP_HAPROXY}"
    echo "   MariaDB1:   ${IP_MARIADB1}"
    echo "   MariaDB2:   ${IP_MARIADB2}"
    echo "   garbd:      ${IP_GARBD}"
    echo "   DB-Port:    ${DB_PORT}"
    echo "   Stats-Port: ${STATS_PORT}"
fi

# ---------------------------------------------------------------------------
# .env erzeugen (falls noch nicht vorhanden)
# ---------------------------------------------------------------------------

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
DB_PORT=${DB_PORT:-3306}
STATS_PORT=${STATS_PORT:-8404}
SUBNET=${SUBNET:-172.18.0.0/24}
GATEWAY=${GATEWAY:-172.18.0.1}
IP_HAPROXY=${IP_HAPROXY:-172.18.0.10}
IP_MARIADB1=${IP_MARIADB1:-172.18.0.11}
IP_MARIADB2=${IP_MARIADB2:-172.18.0.12}
IP_GARBD=${IP_GARBD:-172.18.0.13}
EOF
    chmod 600 .env
    echo ">> .env angelegt - Zugangsdaten stehen dort."
fi

# ---------------------------------------------------------------------------
# Build + Start
# ---------------------------------------------------------------------------

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

# Port-Werte aus .env fuer die Statusausgabe laden
set -a; source .env; set +a

./scripts/status.sh
echo
echo ">> Fertig."
echo "   Datenbank-Endpunkt:  <host>:${DB_PORT:-3306}  (via HAProxy, automatisches Failover)"
echo "   HAProxy-Statusseite: http://<host>:${STATS_PORT:-8404}"
if [ "$USE_PORTOLAN" = "1" ]; then
    echo "   Portolan:            Subnet ${SUBNET}, Ports ${DB_PORT}+${STATS_PORT} registriert."
fi
