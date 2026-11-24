ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

ARG NGINX_VERSION=1.30.7-r0
ARG APP_VERSION=1.0.35

LABEL maintainer="Minh Hua" \
      org.opencontainers.image.title="OmniDrive Pro (Standalone Docker)" \
      org.opencontainers.image.description="All-in-one Multi-Protocol Storage Hub (WebDAV, SMB/Samba, SFTP, FTP), Cloud IDE, Web Terminal, Disk Analytics & Share Links" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.icon="https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png"

ENV APP_VERSION=${APP_VERSION} \
    TZ=America/Denver

# Dấu vân tay phiên bản các gói Alpine quan trọng (Samba, OpenSSH, vsftpd, OpenSSL...). Workflow cập nhật giá trị
# này mỗi khi Alpine phát hành bản vá -> lớp cài gói bên dưới được build lại với 'apk upgrade'.
ARG APK_FINGERPRINT=d4cf421b5a0721d9

# Cài đặt toàn bộ các gói dịch vụ tương đương bản Home Assistant Add-on
RUN echo "Target nginx package: ${NGINX_VERSION} | packages: ${APK_FINGERPRINT}" \
    && apk update && apk upgrade --no-cache && \
    apk add --no-cache \
        bash \
        tzdata \
        jq \
        curl \
        git \
        zip \
        unzip \
        python3 \
        shadow \
        openssl \
        samba \
        samba-common-tools \
        openssh \
        vsftpd \
        nginx \
        nginx-mod-http-dav-ext \
        nginx-mod-http-fancyindex \
    && echo "Installed: $(nginx -v 2>&1)" \
    && mkdir -p /run/nginx /var/lib/nginx/tmp/client_body /var/webdav_root /data/wpro /usr/share/nginx/fancyindex /ssl

# Thư viện front-end (Ace, marked, DOMPurify, js-yaml, JSZip, pdf.js, xterm.js): ghim phiên bản + kiểm tra SHA-256,
# tự host trong image (không phụ thuộc CDN lúc chạy). Dùng chung vendor-fetch.sh với bản Home Assistant Add-on.
COPY vendor-fetch.sh /tmp/vendor-fetch.sh
RUN sh /tmp/vendor-fetch.sh /usr/share/nginx/fancyindex/vendor && rm -f /tmp/vendor-fetch.sh

# Copy FancyIndex UI & Login page
COPY fancyindex/ /usr/share/nginx/fancyindex/

# Copy icon.png vào làm Favicon và iOS Homescreen Icon
COPY icon.png /usr/share/nginx/fancyindex/icon.png
COPY icon.png /usr/share/nginx/fancyindex/apple-touch-icon.png

# Copy script khởi chạy và làm sạch ký tự xuống dòng
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD pgrep nginx >/dev/null && pgrep -f wpro_api.py >/dev/null || exit 1

EXPOSE 8090 445 2222 2121 21000-21002

VOLUME ["/data", "/storage", "/backup", "/ssl"]

ENTRYPOINT ["/entrypoint.sh"]
