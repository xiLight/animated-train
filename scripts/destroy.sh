#!/usr/bin/env bash
# Stoppt den Cluster und gibt Portolan-Ressourcen (Ports, Subnet) frei.
# Optionen:
#   --volumes   Loescht auch die Datenbank-Volumes (Datenverlust!)
set -euo pipefail
cd "$(dirname "$0")/.."

REMOVE_VOLUMES=0
for arg in "$@"; do
    case "$arg" in
        --volumes) REMOVE_VOLUMES=1 ;;
        *) echo "Unbekannte Option: $arg"; exit 1 ;;
    esac
done

SERVICE_NAME="mariadb-cluster"
NET_NAME="${SERVICE_NAME}_db_cluster"

# Liest eine Variable aus der .env (falls vorhanden).
env_val() {
    grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2-
}

# ---------------------------------------------------------------------------
# Cluster stoppen
# ---------------------------------------------------------------------------

echo ">> Stoppe Cluster ..."
if [ "$REMOVE_VOLUMES" = "1" ]; then
    echo "   (--volumes: Datenbank-Volumes werden geloescht!)"
    docker compose down --volumes
else
    docker compose down
fi

# ---------------------------------------------------------------------------
# Portolan-Cleanup
# ---------------------------------------------------------------------------

if command -v portolan &>/dev/null && [ -f .env ]; then
    echo ">> Portolan erkannt - gebe Ressourcen frei ..."

    db_port=$(env_val DB_PORT)
    stats_port=$(env_val STATS_PORT)

    if [ -n "$db_port" ]; then
        portolan free "$db_port" 2>/dev/null && \
            echo "   Port ${db_port} freigegeben." || true
    fi
    if [ -n "$stats_port" ]; then
        portolan free "$stats_port" 2>/dev/null && \
            echo "   Port ${stats_port} freigegeben." || true
    fi

    portolan rm-net "$NET_NAME" 2>/dev/null && \
        echo "   Netzwerk ${NET_NAME} freigegeben." || true
fi

echo ">> Cluster gestoppt."
if [ "$REMOVE_VOLUMES" = "0" ]; then
    echo "   Datenbank-Volumes erhalten (erneutes deploy.sh stellt den Cluster wieder her)."
    echo "   Zum Loeschen: $0 --volumes"
fi
