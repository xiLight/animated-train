# MariaDB HA-Cluster (Galera + HAProxy)

Hochverfügbarer 2-Knoten-MariaDB-Cluster mit automatischem Failover,
automatischem Failback und Selbstheilung. Eine Anwendung verbindet sich
auf **einen** Endpunkt (`<host>:3306`) und merkt von Ausfällen praktisch nichts.

```
                        Anwendung
                            │
                       <host>:${DB_PORT}
                            │
                  ┌─────────▼─────────┐
                  │      HAProxy      │  ${IP_HAPROXY}
                  │  Galera-Healtcheck│  Stats: :${STATS_PORT}
                  └───┬───────────┬───┘
              aktiv   │           │   backup (springt nur bei Ausfall ein)
                  ┌───▼───┐   ┌───▼───┐
                  │mariadb1◄───►mariadb2│   Galera: synchrone Replikation
                  │  .11   │   │  .12  │   (beide Knoten immer identisch)
                  └───┬───┘   └───┬───┘
                      │  ┌─────┐  │
                      └──► garbd◄──┘   ${IP_GARBD}
                         └─────┘   Arbitrator: 3. Quorum-Stimme, keine Daten
```

## Warum dieser Aufbau?

- **Galera (synchrone Multi-Master-Replikation):** Jede Transaktion ist beim
  Commit auf beiden Knoten. Kein Replikations-Lag, kein Datenverlust beim
  Failover. Effizienter geht Sync nicht — es wird nur das Write-Set übertragen.
- **HAProxy Active/Backup:** Es schreibt immer nur ein Knoten (keine
  Schreibkonflikte). Fällt `mariadb1` aus, schaltet HAProxy in ~4–6 s auf
  `mariadb2` um — und automatisch zurück, sobald `mariadb1` wieder *synced* ist.
  Der Healthcheck prüft den echten Galera-Status (`wsrep_local_state`), nicht
  nur "Port offen".
- **garbd (Arbitrator):** Dritte Quorum-Stimme ohne Datenhaltung. Ohne ihn
  würde der überlebende Knoten bei einem Crash des anderen die Mehrheit
  verlieren und sich selbst sperren (Split-Brain-Schutz von Galera).
- **Selbstheilung:** Kommt ein Knoten zurück, holt er sich fehlende
  Transaktionen inkrementell (IST aus dem gcache, 512 MB) oder bei längerem
  Ausfall per Vollkopie (SST via `mariabackup` — blockiert den aktiven Knoten
  dabei **nicht**). Container-Crashes fängt `restart: unless-stopped` ab.

## Quickstart

```bash
git clone <repo> && cd mariadb-cluster
chmod +x scripts/*.sh config/*.sh config/initdb/*.sh haproxy/*.sh   # falls Exec-Bits fehlen
./scripts/deploy.sh        # erzeugt .env mit Zufallspasswörtern, baut, startet, wartet
```

Verbinden: `mariadb -h <host> -P 3306 -u app -p<MARIADB_PASSWORD> appdb`
(Zugangsdaten stehen in `.env`). Root gibt es nur lokal im Container:
`docker exec -it mariadb1 mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"`.

## Portolan-Integration

Ist [portolan](https://github.com/docker-public/portolan) auf dem Host
installiert, erkennt `deploy.sh` das automatisch und:

1. **Holt ein freies Subnet** aus dem konfigurierten Portolan-Pool
2. **Prüft die Ports** `DB_PORT` und `STATS_PORT` auf Verfügbarkeit
3. **Registriert** Subnet und Ports bei Portolan
4. **Schreibt** alle Netzwerk-Variablen in die `.env`

Bei jedem erneuten Deploy werden alte Registrierungen freigegeben und neue
allokiert. `scripts/destroy.sh` räumt alles sauber auf.

Ohne Portolan funktioniert alles wie bisher — die Werte aus `.env` (oder die
Defaults aus `docker-compose.yml`) werden verwendet.

## Skripte

| Skript | Zweck |
|---|---|
| `scripts/deploy.sh` | Erst-Deployment / Update. Portolan-aware. |
| `scripts/destroy.sh` | Stoppt den Cluster und gibt Portolan-Ressourcen frei. |
| `scripts/status.sh` | Container-, Galera- und HAProxy-Status auf einen Blick. |
| `scripts/failover-test.sh` | Killt `mariadb1` live und beweist Failover + Failback. |
| `scripts/backup.sh` | Konsistenter Dump (`--single-transaction`) nach `./backups/`. |
| `scripts/recover.sh` | Nur für den Katastrophenfall (s. unten). |

## Netzwerk-Variablen

Alle IPs und das Subnet sind über `.env` konfigurierbar:

| Variable | Default | Beschreibung |
|---|---|---|
| `SUBNET` | `172.18.0.0/24` | Docker-Netzwerk CIDR |
| `GATEWAY` | `172.18.0.1` | Docker-Netzwerk Gateway |
| `IP_HAPROXY` | `172.18.0.10` | HAProxy-Container |
| `IP_MARIADB1` | `172.18.0.11` | Galera-Knoten 1 |
| `IP_MARIADB2` | `172.18.0.12` | Galera-Knoten 2 |
| `IP_GARBD` | `172.18.0.13` | Galera-Arbitrator |
| `DB_PORT` | `3306` | Host-Port für MariaDB |
| `STATS_PORT` | `8404` | Host-Port für HAProxy-Stats |

## Verhalten im Fehlerfall

| Szenario | Was passiert | Eingriff nötig? |
|---|---|---|
| `mariadb1` crasht | HAProxy schaltet in ~4–6 s auf `mariadb2`; Docker startet `mariadb1` neu, der Knoten synct sich (IST/SST) und übernimmt wieder | nein |
| `mariadb2` crasht | nichts sichtbar, `mariadb1` läuft weiter; `mariadb2` heilt sich selbst | nein |
| Host-Reboot / `compose down`+`up` | Knoten mit `safe_to_bootstrap=1` fährt den Cluster automatisch wieder hoch | nein |
| Beide Knoten crashen gleichzeitig | `pc.recovery` stellt den Cluster meist automatisch wieder her | meist nein |
| Kompletter harter Tod, kein Autostart | — | `./scripts/recover.sh` (bootstrappt vom Knoten mit dem neuesten Stand) |

## Wichtige Hinweise

- **Subnetz:** Per Default `172.18.0.0/24`. Kollidiert es, entweder Portolan
  nutzen (automatisch) oder die Netzwerk-Variablen in `.env` manuell anpassen.
- **Zeilenenden:** Die `.sh`/`.cfg`-Dateien werden in Container gemountet und
  müssen LF-Zeilenenden haben (regelt `.gitattributes`; unter Windows nichts
  mit CRLF speichern).
- **Schreiben nur über HAProxy (`:3306`):** Die Knoten sind bewusst nicht
  direkt am Host exponiert. Direkt auf beide Knoten gleichzeitig zu schreiben
  funktioniert zwar (Multi-Master), erhöht aber das Konfliktrisiko.
- **Monitoring:** HAProxy-Statusseite unter `http://<host>:${STATS_PORT}`, Details per
  `./scripts/status.sh`.
- **Galera-Eigenheiten:** Nur InnoDB-Tabellen werden repliziert; jede Tabelle
  braucht einen Primary Key; `LOCK TABLES` wird nicht unterstützt.
- **Backups:** Replikation ersetzt kein Backup (ein `DROP TABLE` repliziert
  sich synchron auf beide Knoten…). `scripts/backup.sh` per Cron einplanen.
