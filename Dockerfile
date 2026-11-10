ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

ARG NGINX_VERSION=1.30.6-r0
ARG APP_VERSION=1.0.29

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

# Copy icon.png vào làm Favicon và iOS Homescreen Icon
COPY icon.png /usr/share/nginx/fancyindex/icon.png
COPY icon.png /usr/share/nginx/fancyindex/apple-touch-icon.png

# Copy script khởi chạy
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
