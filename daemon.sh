#!/bin/sh
# Start script for JDownloader 2 headless. Based on jaymoulin/jdownloader (MIT).
APP=/opt/JDownloader/app
mkdir -p "$APP/cfg" "$APP/libs" "$APP/tmp"
rm -f "$APP"/JDownloader.jar.* "$APP/JDownloader.pid" 2>/dev/null

# Optional PUID/GID when started as root
if [ -n "$PUID" ] && [ "$(id -u)" -eq 0 ]; then
    adduser jdown -D 2>/dev/null || useradd jdown 2>/dev/null
    usermod -u "$PUID" jdown
fi
if [ -n "$GID" ] && [ "$(id -u)" -eq 0 ]; then
    groupmod -g "$GID" jdown >/dev/null 2>&1 || usermod -g "$GID" jdown
fi

# MyJDownloader credentials: docker secrets preferred, env as fallback
if [ -n "$FILE_MYJD_USER" ] && [ -n "$FILE_MYJD_PASSWORD" ]; then
    MYJD_USER=$(cat "/run/secrets/$FILE_MYJD_USER"); MYJD_PASSWORD=$(cat "/run/secrets/$FILE_MYJD_PASSWORD")
fi
if [ -n "$MYJD_USER" ] && [ -n "$MYJD_PASSWORD" ]; then
    CFG="$APP/cfg/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json"
    [ -f "$CFG" ] || cp /opt/JDownloader/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json.dist "$CFG"
    pw=$(printf '%s' "$MYJD_PASSWORD" | sed 's/[\\/&"]/\\&/g'); em=$(printf '%s' "$MYJD_USER" | sed 's/[\\/&"]/\\&/g')
    sed -Ei "s/\"password\":\"[^\"]*\"/\"password\":\"$pw\"/; s/\"email\":\"[^\"]*\"/\"email\":\"$em\"/" "$CFG"
fi
if [ -n "$MYJD_DEVICE_NAME" ] && [ -f "$APP/cfg/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json" ]; then
    dn=$(printf '%s' "$MYJD_DEVICE_NAME" | sed 's/[\\/&"]/\\&/g')
    sed -Ei "s/\"devicename\":\"[^\"]*\"/\"devicename\":\"$dn\"/" "$APP/cfg/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json"
fi

# Debug helper: create jdownloader-block.txt in the download folder to keep the container idle
[ -f /opt/JDownloader/Downloads/jdownloader-block.txt ] && sleep 1000000

[ -f "$APP/libs/sevenzipjbinding1509.jar" ] || cp /opt/JDownloader/libs/*.jar "$APP/libs/"
if [ ! -f "$APP/JDownloader.jar" ] || ! unzip -l "$APP/JDownloader.jar" >/dev/null 2>&1; then
    rm -f "$APP/Core.jar" 2>/dev/null
    cp /opt/JDownloader/JDownloader.jar "$APP/"
fi

# Unraid default: files 666 / dirs 777 so SMB users can delete what JD creates
if echo "$UMASK" | grep -Eq '^0?[0-7]{3}$'; then umask "$UMASK"; fi

# JVM tuning for small, old CPUs: Serial GC, bounded heap, auto CDS archive, ChaCha20-first TLS
JOPTS="-Djava.awt.headless=true -Dsun.jnu.encoding=UTF-8 -Dfile.encoding=UTF-8 \
 -XX:+UseSerialGC -Xms64m -Xmx${JD_HEAP} -XX:+UseStringDeduplication \
 -XX:+AutoCreateSharedArchive -XX:SharedArchiveFile=$APP/tmp/jd-cds.jsa"
# Compact object headers exist since Java 24 (saves heap)
JV=$("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 | sed -n "s/.*java.specification.version = //p")
[ "${JV:-0}" -ge 24 ] 2>/dev/null && JOPTS="$JOPTS -XX:+UseCompactObjectHeaders"
[ -n "$JD_TLS_CIPHERS" ] && JOPTS="$JOPTS -Djdk.tls.client.cipherSuites=$JD_TLS_CIPHERS"

cd "$APP"
start_jd() {
    if [ -n "$PUID" ] && [ "$(id -u)" -eq 0 ]; then
        chown -R "${PUID}:${GID:-100}" /opt/JDownloader/app
        su jdown -c "umask ${UMASK:-0000}; $JAVA_HOME/bin/java $JOPTS $VMARGS -jar $APP/JDownloader.jar -norestart" &
    else
        "$JAVA_HOME/bin/java" $JOPTS $VMARGS -jar "$APP/JDownloader.jar" -norestart &
    fi
    PID=$!
}

# Keep JDownloader running: after a self-update JD exits (or hands over to a new java
# process); restart it until the container is asked to stop.
STOP=0
trap 'STOP=1; [ -n "$PID" ] && kill -TERM "$PID" 2>/dev/null' TERM INT
start_jd
while [ "$STOP" -eq 0 ]; do
    wait "$PID" 2>/dev/null
    [ "$STOP" -eq 1 ] && break
    PID=$(pgrep -f 'JDownloader.jar' | head -1)
    if [ -z "$PID" ]; then
        echo "JDownloader exited (update/restart) - starting it again"
        sleep 3
        start_jd
    fi
done
[ -n "$PID" ] && wait "$PID" 2>/dev/null
