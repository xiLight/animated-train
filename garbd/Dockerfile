# Galera Arbitrator (garbd): vollwertige Quorum-Stimme ohne Datenhaltung.
# Verhindert, dass der ueberlebende Knoten bei einem Crash des anderen die
# Mehrheit verliert und sich aus Sicherheitsgruenden selbst sperrt.
FROM mariadb:11.4

USER mysql
ENTRYPOINT ["garbd"]
