FROM haproxy:3.0-alpine

USER root
# mariadb-client fuer den Galera-Healthcheck, socat fuer die Admin-Socket-Abfragen,
# gettext fuer envsubst (Template-Rendering der HAProxy-Config)
RUN apk add --no-cache bash mariadb-client socat gettext

COPY galera-check.sh /usr/local/bin/galera-check.sh
RUN chmod 755 /usr/local/bin/galera-check.sh

COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg.tpl
COPY haproxy-entrypoint.sh /usr/local/bin/haproxy-entrypoint.sh
RUN chmod 755 /usr/local/bin/haproxy-entrypoint.sh

USER haproxy
ENTRYPOINT ["/usr/local/bin/haproxy-entrypoint.sh"]
