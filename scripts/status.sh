#!/usr/bin/env bash
# Zeigt Container-, Galera- und HAProxy-Status auf einen Blick.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Container ==="
docker compose ps --format "table {{.Name}}\t{{.Status}}"

echo
echo "=== Galera-Status ==="
for node in mariadb1 mariadb2; do
    health=$(docker inspect -f '{{.State.Health.Status}}' "$node" 2>/dev/null || echo "nicht gestartet")
    state=$(docker exec "$node" mariadb -uhealth -N -B -e \
        "SHOW STATUS WHERE Variable_name IN ('wsrep_local_state_comment','wsrep_cluster_size','wsrep_cluster_status')" 2>/dev/null \
        | awk '{printf "%s=%s  ", $1, $2}') || state=""
    echo "  $node: health=$health  ${state:-<keine Antwort>}"
done

echo
echo "=== HAProxy-Routing ==="
docker compose exec -T haproxy sh -c 'echo "show stat" | socat stdio /tmp/haproxy.sock' 2>/dev/null \
    | awk -F, '$1 == "mariadb" && $2 != "FRONTEND" && $2 != "BACKEND" {
        printf "  %-10s %-6s %s\n", $2, $18, ($2 == "mariadb2" ? "(backup)" : "(primaer)")
    }' || echo "  HAProxy nicht erreichbar"
