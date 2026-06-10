#!/bin/bash
# HAProxy external-check fuer Galera-Knoten.
# Aufruf durch HAProxy: <proxy_addr> <proxy_port> <server_addr> <server_port>
# Exit 0 = Knoten darf Traffic bekommen, Exit 1 = Knoten aus der Rotation.
#
# Ein blosser TCP/MySQL-Ping reicht nicht: ein Galera-Knoten kann erreichbar
# sein, aber nicht synchronisiert (dann lehnt er Queries ab oder liefert
# veraltete Daten). Deshalb wird der echte wsrep-Status geprueft:
#   4 = Synced            -> gesund
#   2 = Donor/Desynced    -> gesund (mit mariabackup-SST weiterhin nutzbar;
#                            wichtig, sonst faellt der aktive Knoten aus der
#                            Rotation, waehrend er den anderen wieder aufbaut)

HOST="${3:-${HAPROXY_SERVER_ADDR:-}}"
PORT="${4:-${HAPROXY_SERVER_PORT:-3306}}"

STATE=$(mariadb -h "$HOST" -P "$PORT" -u health --connect-timeout=2 -N -B \
    -e "SHOW GLOBAL STATUS LIKE 'wsrep_local_state'" 2>/dev/null | awk '{print $2}')

case "$STATE" in
    4|2) exit 0 ;;
    *)   exit 1 ;;
esac
