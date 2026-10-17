# syntax=docker/dockerfile:1
# JDownloader 2 headless (MyJDownloader) on Alpine/musl with a slim Java 27 runtime.
# Tuned for old x86-64 CPUs without AES-NI (ChaCha20-first TLS) and low core counts.
# Based on the scripts of jaymoulin/jdownloader (MIT).

ARG ALPINE_VERSION=3.23
# Liberica JDK (musl, full – includes jmods for jlink) as tarball – the bellsoft container images use CPU instructions
# that old CPUs (e.g. AMD Athlon II without SSSE3/SSE4) do not have and crash with SIGILL.
ARG LIBERICA_URL=https://github.com/bell-sw/Liberica/releases/download/27+36/bellsoft-jdk27+36-linux-x64-musl.tar.gz
ARG LIBERICA_SHA256=637b00461afce5f26a87289db8f8f3867434324eed292a4dfe8d7602725518c6

# ---- 1) build a minimal Java runtime with only the modules JDownloader needs ----
FROM alpine:${ALPINE_VERSION} AS jre
ARG LIBERICA_URL
ARG LIBERICA_SHA256
RUN apk add --no-cache wget binutils \
 && wget -q -O /tmp/jdk.tgz "${LIBERICA_URL}" \
 && echo "${LIBERICA_SHA256}  /tmp/jdk.tgz" | sha256sum -c - \
 && mkdir -p /opt/jdk && tar -xzf /tmp/jdk.tgz -C /opt/jdk --strip-components=1 \
 && /opt/jdk/bin/jlink \
      --add-modules java.se,jdk.crypto.ec,jdk.crypto.cryptoki,jdk.unsupported,jdk.zipfs,jdk.charsets,jdk.localedata,jdk.naming.dns,jdk.httpserver,jdk.management,jdk.net,jdk.unsupported.desktop \
      --strip-debug --no-man-pages --no-header-files --compress=zip-6 \
      --output /opt/jre

# ---- 2) runtime image ----
FROM alpine:${ALPINE_VERSION}
ARG VERSION=dev
LABEL org.opencontainers.image.title="jdownloader-musl" \
      org.opencontainers.image.description="JDownloader 2 headless for MyJDownloader – Alpine/musl, slim Java 27, tuned for old CPUs" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache ca-certificates libstdc++ ffmpeg procps shadow fontconfig ttf-dejavu \
 && update-ca-certificates && fc-cache -f

COPY --from=jre /opt/jre /opt/jre
ENV JAVA_HOME=/opt/jre \
    PATH=/opt/jre/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    XDG_DOWNLOAD_DIR=/opt/JDownloader/Downloads \
    UMASK=0000 \
    JD_HEAP=512m \
    JD_TLS_CIPHERS=TLS_CHACHA20_POLY1305_SHA256,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 \
    VMARGS=

ADD https://installer.jdownloader.org/JDownloader.jar /opt/JDownloader/JDownloader.jar
COPY rootfs/libs/*.jar /opt/JDownloader/libs/
COPY rootfs/default-config.json.dist /opt/JDownloader/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json.dist
COPY rootfs/configure.sh /usr/bin/configure
COPY daemon.sh /opt/JDownloader/daemon.sh
RUN chmod 0755 /usr/bin/configure /opt/JDownloader/daemon.sh && chmod 0644 /opt/JDownloader/JDownloader.jar \
 && mkdir -p /opt/JDownloader/app /opt/JDownloader/Downloads \
 && chmod 0777 /opt/JDownloader/app /opt/JDownloader/Downloads

WORKDIR /opt/JDownloader
VOLUME ["/opt/JDownloader/app", "/opt/JDownloader/Downloads"]
EXPOSE 3129
CMD ["/opt/JDownloader/daemon.sh"]
