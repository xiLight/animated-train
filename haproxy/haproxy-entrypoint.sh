#!/bin/bash
# Entrypoint-Wrapper fuer HAProxy: rendert die Konfiguration aus
# Umgebungsvariablen und startet dann HAProxy.
set -euo pipefail

: "${IP_MARIADB1:?IP_MARIADB1 fehlt}"
: "${IP_MARIADB2:?IP_MARIADB2 fehlt}"

# Template rendern - nur die explizit benoetigten Variablen ersetzen,
# damit andere $-Zeichen in der Konfiguration unangetastet bleiben.
envsubst '${IP_MARIADB1} ${IP_MARIADB2}' \
    < /usr/local/etc/haproxy/haproxy.cfg.tpl \
    > /tmp/haproxy.cfg

echo "[haproxy-entrypoint] Config gerendert: mariadb1=${IP_MARIADB1}, mariadb2=${IP_MARIADB2}"
exec haproxy -f /tmp/haproxy.cfg "$@"
