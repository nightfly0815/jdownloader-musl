# jdownloader-musl

JDownloader 2 **headless** für [MyJDownloader](https://my.jdownloader.org) – als schlankes Docker-Image für Unraid,
optimiert für **alte x86-64-CPUs** (getestet auf HP ProLiant MicroServer N36L, AMD Athlon II Neo, ohne AES-NI/SSE4).

## Was ist anders als beim Original (jaymoulin/jdownloader)?

| | |
|---|---|
| Basis | Alpine Linux (musl) |
| Java | **Java 27** (BellSoft Liberica, musl), per `jlink` auf die nötigen Module reduziert (~100 MB) |
| TLS | **ChaCha20 zuerst** – auf CPUs ohne AES-NI deutlich schnellere HTTPS-Downloads (abschaltbar) |
| JVM | Serial GC, begrenzter Heap (`JD_HEAP`), Compact Object Headers, automatischer CDS-Cache |
| Rechte | `UMASK=0000` (Unraid-Standard) – neue Dateien/Ordner sind über SMB löschbar |
| Updates | JD aktualisiert sich selbst im Container; der Container startet JD danach automatisch neu |
| Speicher | komplettes JD-Programmverzeichnis als Volume (`/opt/JDownloader/app`) |
| Entpacken | 7-Zip-JBinding (musl-Variante, von JD selbst geladen), ffmpeg enthalten |

Hinweis zu Java 26: Dort bleiben die Hoster-Icons in MyJDownloader leer (JD-HTTP-Server und ein vorzeitiges
`flush()` in `ImageIO.write`). Java 21, 25 und 27 sind nicht betroffen.

## Unraid

Template: [`unraid/jdownloader-musl.xml`](unraid/jdownloader-musl.xml) – nach
`/boot/config/plugins/dockerMan/templates-user/` kopieren, dann unter *Docker → Add Container* auswählen.

## Variablen

| Variable | Standard | Bedeutung |
|---|---|---|
| `MYJD_USER` / `MYJD_PASSWORD` | – | MyJDownloader-Zugang (alternativ Docker-Secrets `FILE_MYJD_USER`/`FILE_MYJD_PASSWORD`) |
| `MYJD_DEVICE_NAME` | – | Gerätename in MyJDownloader |
| `UMASK` | `0000` | Rechte neuer Dateien |
| `JD_HEAP` | `512m` | maximaler Java-Heap |
| `JD_TLS_CIPHERS` | ChaCha20-Liste | leer = Java-Standard (besser bei CPUs mit AES-NI) |
| `VMARGS` | – | zusätzliche JVM-Optionen |

## Bauen

```sh
docker build -t jdownloader-musl .
# andere Java-Version, z. B. 25 LTS:
docker build --build-arg LIBERICA_URL=<tar.gz-URL> --build-arg LIBERICA_SHA256=<sha256> -t jdownloader-musl .
```

Wichtig: die fertigen `bellsoft/liberica-runtime-container`-Images laufen auf alten CPUs **nicht** (SIGILL) –
deshalb wird Java hier aus dem Liberica-Tarball gebaut.

## Lizenz

MIT. Start- und Konfigurationsskripte basieren auf [jaymoulin/docker-jdownloader](https://github.com/jaymoulin/docker-jdownloader) (MIT).
JDownloader ist Software der AppWork GmbH und wird beim Build von installer.jdownloader.org geladen.
