ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

ARG NGINX_VERSION=1.30.6-r0
ARG APP_VERSION=1.0.30

LABEL maintainer="Minh Hua" \
      org.opencontainers.image.title="OmniDrive Pro (Standalone Docker)" \
      org.opencontainers.image.description="All-in-one Multi-Protocol Storage Hub (WebDAV, SMB/Samba, SFTP, FTP), Cloud IDE, Web Terminal, Disk Analytics & Share Links" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.icon="https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png"

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

# Self-host front-end libraries (no runtime CDN dependency, no third-party script risk).
# curl -f makes the build FAIL on any download error instead of shipping a broken UI.
RUN set -eux; \
    V=/usr/share/nginx/fancyindex/vendor; \
    mkdir -p "$V/ace"; \
    ACE=https://cdn.jsdelivr.net/npm/ace-builds@1.36.2/src-min-noconflict; \
    for f in ace ext-searchbox theme-one_dark mode-yaml mode-json mode-python mode-sh \
             mode-javascript mode-typescript mode-html mode-css mode-php mode-xml mode-sql \
             mode-markdown mode-ini mode-toml mode-dockerfile; do \
        curl -fsSL --retry 3 "$ACE/$f.js" -o "$V/ace/$f.js"; \
    done; \
    curl -fsSL --retry 3 https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js        -o "$V/marked.min.js"; \
    curl -fsSL --retry 3 https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js           -o "$V/purify.min.js"; \
    curl -fsSL --retry 3 https://cdnjs.cloudflare.com/ajax/libs/js-yaml/4.1.0/js-yaml.min.js       -o "$V/js-yaml.min.js"; \
    curl -fsSL --retry 3 https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js          -o "$V/jszip.min.js"; \
    curl -fsSL --retry 3 https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js         -o "$V/pdf.min.js"; \
    curl -fsSL --retry 3 https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js  -o "$V/pdf.worker.min.js"; \
    curl -fsSL --retry 3 https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.min.css                -o "$V/xterm.min.css"; \
    curl -fsSL --retry 3 https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js                 -o "$V/xterm.min.js"; \
    # sanity check: every file must be non-empty
    find "$V" -type f -size -100c -print -exec false {} +

# Copy FancyIndex UI & Login page
COPY fancyindex/ /usr/share/nginx/fancyindex/

# Copy icon.png vào làm Favicon và iOS Homescreen Icon
COPY icon.png /usr/share/nginx/fancyindex/icon.png
COPY icon.png /usr/share/nginx/fancyindex/apple-touch-icon.png

# Copy script khởi chạy và làm sạch ký tự xuống dòng
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Các cổng dịch vụ: WebDAV/UI (8090), SMB (445), SFTP (2222), FTP (2121 + Passive 21000-21002)
EXPOSE 8090 445 2222 2121 21000-21002

VOLUME ["/data", "/storage", "/backup", "/ssl"]

ENTRYPOINT ["/entrypoint.sh"]
