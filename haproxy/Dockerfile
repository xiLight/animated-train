FROM haproxy:3.0-alpine

USER root
# mariadb-client fuer den Galera-Healthcheck, socat fuer die Admin-Socket-Abfragen
RUN apk add --no-cache bash mariadb-client socat

COPY galera-check.sh /usr/local/bin/galera-check.sh
RUN chmod 755 /usr/local/bin/galera-check.sh

USER haproxy
