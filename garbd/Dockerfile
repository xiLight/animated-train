# Galera Arbitrator (garbd): vollwertige Quorum-Stimme ohne Datenhaltung.
# Verhindert, dass der ueberlebende Knoten bei einem Crash des anderen die
# Mehrheit verliert und sich aus Sicherheitsgruenden selbst sperrt.
FROM mariadb:11.4

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends galera-arbitrator-4 \
 && rm -rf /var/lib/apt/lists/*

USER mysql
WORKDIR /tmp
ENTRYPOINT ["garbd"]
