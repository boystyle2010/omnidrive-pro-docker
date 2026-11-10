ARG ALPINE_VERSION=3.21
FROM alpine:${ALPINE_VERSION}

ARG NGINX_VERSION=1.26.3-r0
ARG APP_VERSION=1.0.28

LABEL maintainer="Minh Hua" \
      org.opencontainers.image.title="OmniDrive Pro (Standalone Docker)" \
      org.opencontainers.image.description="All-in-one Multi-Protocol Storage Hub (WebDAV, SMB/Samba, SFTP, FTP), Cloud IDE, Web Terminal, Disk Analytics & Share Links" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV APP_VERSION=${APP_VERSION} \
    TZ=America/Denver

# Cài đặt toàn bộ các gói dịch vụ tương đương bản Home Assistant Add-on
RUN apk update && \
    apk add --no-cache \
        bash \
        tzdata \
        jq \
        curl \
        git \
        zip \
        unzip \
        python3 \
        apache2-utils \
        openssl \
        samba \
        samba-common-tools \
        openssh \
        vsftpd \
        nginx \
        nginx-mod-http-dav-ext \
        nginx-mod-http-fancyindex \
    && mkdir -p /run/nginx /var/lib/nginx/tmp/client_body /var/webdav_root /data/wpro /usr/share/nginx/fancyindex /ssl

# Copy giao diện FancyIndex & Login
COPY fancyindex/ /usr/share/nginx/fancyindex/

# Copy script khởi chạy
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Các cổng dịch vụ: WebDAV/UI (8090), SMB (445), SFTP (2222), FTP (2121 + Passive 21000-21002)
EXPOSE 8090 445 2222 2121 21000-21002

VOLUME ["/data", "/storage", "/backup", "/ssl"]

ENTRYPOINT ["/entrypoint.sh"]
