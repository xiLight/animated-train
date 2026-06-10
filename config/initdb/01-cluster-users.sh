#!/bin/bash
# Legt die Cluster-internen Benutzer an.
# Laeuft nur einmal bei der Erst-Initialisierung des Datenverzeichnisses;
# auf dem Beitritts-Knoten wird der Stand danach ohnehin per SST ersetzt.
# Hinweis: bewusst kein "set -u" - der MariaDB-Entrypoint sourct dieses
# Skript, wenn das Exec-Bit fehlt, und wuerde sich daran verschlucken.

mariadb --protocol=socket -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
-- SST-Benutzer fuer mariabackup (wird auf der Donor-Seite benoetigt)
CREATE USER IF NOT EXISTS 'sst'@'localhost' IDENTIFIED BY '${GALERA_SST_PASSWORD}';
GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR ON *.* TO 'sst'@'localhost';

-- Healthcheck-Benutzer: bewusst ohne Passwort, aber ohne jegliche Rechte
-- (kann nur SHOW STATUS) und auf localhost bzw. die HAProxy-IP beschraenkt.
CREATE USER IF NOT EXISTS 'health'@'localhost';
CREATE USER IF NOT EXISTS 'health'@'${HAPROXY_IP}';
FLUSH PRIVILEGES;
SQL
