#!/bin/bash
# Galera-aware Entrypoint-Wrapper fuer das offizielle mariadb-Image.
# 1. Rendert die Galera-Konfiguration aus Umgebungsvariablen.
# 2. Entscheidet sicher, ob dieser Knoten den Cluster bootstrappt oder beitritt.
# Danach wird an den Original-Entrypoint des Images uebergeben.
set -euo pipefail

: "${GALERA_NODE_NAME:?GALERA_NODE_NAME fehlt}"
: "${GALERA_NODE_IP:?GALERA_NODE_IP fehlt}"
: "${GALERA_CLUSTER_ADDRESS:?GALERA_CLUSTER_ADDRESS fehlt}"
: "${GALERA_SST_PASSWORD:?GALERA_SST_PASSWORD fehlt}"

GALERA_CLUSTER_NAME="${GALERA_CLUSTER_NAME:-mariadb-cluster}"
GALERA_GCACHE_SIZE="${GALERA_GCACHE_SIZE:-512M}"
INNODB_BUFFER_POOL_SIZE="${INNODB_BUFFER_POOL_SIZE:-256M}"
DATADIR=/var/lib/mysql
GRASTATE="$DATADIR/grastate.dat"

log() { echo "[galera-entrypoint] $*"; }

cat > /etc/mysql/conf.d/zz-galera.cnf <<EOF
[mysqld]
bind-address=0.0.0.0
skip-name-resolve

# Galera-Pflichteinstellungen
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
innodb_flush_log_at_trx_commit=2
innodb_buffer_pool_size=${INNODB_BUFFER_POOL_SIZE}

wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name=${GALERA_CLUSTER_NAME}
wsrep_cluster_address=${GALERA_CLUSTER_ADDRESS}
wsrep_node_name=${GALERA_NODE_NAME}
wsrep_node_address=${GALERA_NODE_IP}

# SST via mariabackup: blockiert den Donor nicht -> der aktive Knoten bleibt
# waehrend der Selbstheilung des anderen Knotens voll nutzbar.
wsrep_sst_method=mariabackup
wsrep_sst_auth=sst:${GALERA_SST_PASSWORD}

# Grosser gcache: nach kurzen Ausfaellen reicht ein inkrementeller Sync (IST)
# statt einer vollen Kopie (SST). pc.recovery stellt den Cluster nach einem
# gleichzeitigen Crash beider Knoten automatisch wieder her.
wsrep_provider_options="gcache.size=${GALERA_GCACHE_SIZE};pc.recovery=true"
EOF
chown root:mysql /etc/mysql/conf.d/zz-galera.cnf
chmod 640 /etc/mysql/conf.d/zz-galera.cnf

peer_reachable() {
    local peer host port
    for peer in ${GALERA_PEERS:-}; do
        host="${peer%:*}"
        port="${peer#*:}"
        if timeout 2 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
            log "Peer ${peer} ist erreichbar."
            return 0
        fi
    done
    return 1
}

BOOTSTRAP=0
if [ "${GALERA_FORCE_BOOTSTRAP:-0}" = "1" ]; then
    if peer_reachable; then
        log "FORCE_BOOTSTRAP gesetzt, aber ein Peer laeuft bereits -> Bootstrap verweigert (Split-Brain-Schutz), trete normal bei."
    else
        log "FORCE_BOOTSTRAP: erzwinge Cluster-Bootstrap von diesem Knoten."
        [ -f "$GRASTATE" ] && sed -i 's/^safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "$GRASTATE"
        BOOTSTRAP=1
    fi
elif [ ! -s "$GRASTATE" ]; then
    # Frisches Datenverzeichnis: nur der designierte Erstknoten darf einen
    # neuen Cluster gruenden - und nur, wenn kein bestehender Cluster laeuft.
    if [ "${GALERA_BOOTSTRAP_IF_NEW:-0}" = "1" ] && ! peer_reachable; then
        log "Kein Cluster-Zustand vorhanden und keine Peers erreichbar -> gruende neuen Cluster."
        BOOTSTRAP=1
    fi
elif grep -q '^safe_to_bootstrap: 1' "$GRASTATE" && ! peer_reachable; then
    # Sauberer Komplett-Shutdown (z.B. docker compose down): der zuletzt
    # gestoppte Knoten traegt safe_to_bootstrap=1 und faehrt den Cluster
    # selbststaendig wieder hoch.
    log "safe_to_bootstrap=1 und keine Peers erreichbar -> starte Cluster neu."
    BOOTSTRAP=1
fi

ARGS=()
[ "$BOOTSTRAP" = "1" ] && ARGS+=(--wsrep-new-cluster)
log "Starte mariadbd (node=${GALERA_NODE_NAME}, bootstrap=${BOOTSTRAP})."
exec docker-entrypoint.sh mariadbd "${ARGS[@]}" "$@"
