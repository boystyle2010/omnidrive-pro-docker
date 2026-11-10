#!/usr/bin/env bash
set -e

# Hàm hiển thị Log
log_info()  { echo -e "\033[1;34m[INFO]\033[0m  $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
exit_nok()  { log_error "$*"; exit 1; }

is_true() {
    case "${1,,}" in
        true|1|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

APP_VERSION="${APP_VERSION:-1.0.28}"
log_info "--------------------------------------------------------"
log_info " Initializing OmniDrive Pro v${APP_VERSION} (Standalone Docker)"
log_info "--------------------------------------------------------"

CONFIG_PATH="/data/options.json"
HTPASSWD_FILE="/etc/nginx/webdav.htpasswd"
NGINX_CONF="/etc/nginx/nginx.conf"
ROOT_DIR="/var/webdav_root"
WEBDAV_PORT="${WEBDAV_PORT:-8090}"
API_PORT=8098
WPRO_DATA="/data/wpro"

mkdir -p "$WPRO_DATA" /backup /storage /media /share /ssl /mnt
touch "$WPRO_DATA/audit.jsonl"
[ ! -f "$WPRO_DATA/shares.json" ] && echo "{}" > "$WPRO_DATA/shares.json"

# Tự động tạo /data/options.json từ Biến môi trường (ENV) nếu chưa tồn tại
if [ ! -f "$CONFIG_PATH" ]; then
    log_info "Generating default configuration at ${CONFIG_PATH}..."
    DEFAULT_USER="${OMNI_USER:-admin}"
    DEFAULT_PASS="${OMNI_PASS:-changeme_strong_password}"
    
    cat <<EOF > "$CONFIG_PATH"
{
  "unified_root": ${UNIFIED_ROOT:-true},
  "smb_enabled": ${SMB_ENABLED:-true},
  "sftp_enabled": ${SFTP_ENABLED:-true},
  "ftp_enabled": ${FTP_ENABLED:-true},
  "ssl": ${SSL:-false},
  "certfile": "${CERTFILE:-fullchain.pem}",
  "keyfile": "${KEYFILE:-privkey.pem}",
  "max_upload_size": "${MAX_UPLOAD_SIZE:-0}",
  "fancy_ui": ${FANCY_UI:-true},
  "show_dotfiles": ${SHOW_DOTFILES:-true},
  "log_level": "${LOG_LEVEL:-info}",
  "users": [
    {
      "username": "${DEFAULT_USER}",
      "password": "${DEFAULT_PASS}"
    }
  ],
  "shares": [
    { "name": "storage", "path": "/storage", "read_only": false, "allowed_users": [] },
    { "name": "media",   "path": "/media",   "read_only": false, "allowed_users": [] },
    { "name": "share",   "path": "/share",   "read_only": false, "allowed_users": [] },
    { "name": "backup",  "path": "/backup",  "read_only": false, "allowed_users": [] }
  ]
}
EOF
fi

cfg_val() {
    jq -r "$1" "$CONFIG_PATH"
}

# 1. Đọc cấu hình từ /data/options.json
UNIFIED_ROOT=$(cfg_val '.unified_root // true')
SMB_ENABLED=$(cfg_val '.smb_enabled // true')
SFTP_ENABLED=$(cfg_val '.sftp_enabled // true')
FTP_ENABLED=$(cfg_val '.ftp_enabled // true')
SSL=$(cfg_val '.ssl // false')
CERTFILE=$(cfg_val '.certfile // "fullchain.pem"')
KEYFILE=$(cfg_val '.keyfile // "privkey.pem"')
MAX_UPLOAD=$(cfg_val '.max_upload_size // "0"')
FANCY_UI=$(cfg_val '.fancy_ui // true')
SHOW_DOTFILES=$(cfg_val '.show_dotfiles // true')
LOG_LEVEL=$(cfg_val '.log_level // "info"')
PASV_ADDRESS="${FTP_PASV_ADDRESS:-}"

# 2. Chuẩn bị thư mục gốc hợp nhất (/var/webdav_root)
mkdir -p "$ROOT_DIR"
rm -rf "${ROOT_DIR:?}"/*

# 2A. Gắn các thư mục được khai báo trong options.json
SHARES_COUNT=$(jq '.shares | length' "$CONFIG_PATH")
for (( i=0; i<SHARES_COUNT; i++ )); do
    SHARE_NAME=$(jq -r ".shares[$i].name" "$CONFIG_PATH")
    SHARE_PATH=$(jq -r ".shares[$i].path" "$CONFIG_PATH")

    if [ ! -d "$SHARE_PATH" ]; then
        mkdir -p "$SHARE_PATH"
    fi
    ln -sfn "$SHARE_PATH" "${ROOT_DIR}/${SHARE_NAME}"
done

# 2B. Nếu bạn mount toàn bộ gốc máy chủ Linux vào /host_root -> Tự động hiện lên
if [ -d "/host_root" ] && [ -n "$(ls -A /host_root 2>/dev/null)" ]; then
    ln -sfn "/host_root" "${ROOT_DIR}/host_system"
    log_info "Full Host Filesystem mounted at: /host_system"
fi

# 2C. Tự động phát hiện và gắn mọi thư mục được mount vào /mnt/<tên_thư_mục>
for dir in /mnt/*; do
    if [ -d "$dir" ]; then
        MNT_NAME=$(basename "$dir")
        if [ ! -e "${ROOT_DIR}/${MNT_NAME}" ]; then
            ln -sfn "$dir" "${ROOT_DIR}/${MNT_NAME}"
            log_info "Auto-mounted volume: /mnt/${MNT_NAME} -> /${MNT_NAME}"
        fi
    fi
done

# 3. Tạo tài khoản cho WebDAV (htpasswd) VÀ Linux System Users (cho SMB, SFTP & FTP)
rm -f "$HTPASSWD_FILE"
touch "$HTPASSWD_FILE"

USERS_COUNT=$(jq '.users | length' "$CONFIG_PATH")
if [ "$USERS_COUNT" -eq 0 ]; then
    exit_nok "Error: you must define at least one account under 'users' in ${CONFIG_PATH}!"
fi

FIRST_USER=""
for (( i=0; i<USERS_COUNT; i++ )); do
    USERNAME=$(jq -r ".users[$i].username" "$CONFIG_PATH")
    PASSWORD=$(jq -r ".users[$i].password" "$CONFIG_PATH")
    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        [ -z "$FIRST_USER" ] && FIRST_USER="$USERNAME"
        htpasswd -Bb "$HTPASSWD_FILE" "$USERNAME" "$PASSWORD" >/dev/null 2>&1

        if ! id "$USERNAME" >/dev/null 2>&1; then
            adduser -D -H -h "$ROOT_DIR" -s /bin/bash -G root "$USERNAME" >/dev/null 2>&1 || true
        fi
        echo "${USERNAME}:${PASSWORD}" | chpasswd >/dev/null 2>&1 || true
        (echo "$PASSWORD"; echo "$PASSWORD") | smbpasswd -a -s "$USERNAME" >/dev/null 2>&1 || true
        smbpasswd -e "$USERNAME" >/dev/null 2>&1 || true

        log_info "Provisioned multi-protocol account: ${USERNAME}"
    fi
done

chmod -R 775 "$ROOT_DIR" || true

# 4. Khởi động SMB / Samba Server (Port 445)
if is_true "$SMB_ENABLED"; then
    mkdir -p /var/lib/samba/private /var/log/samba /run/samba
    cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server string = OmniDrive Pro (Docker Storage Hub)
   security = user
   map to guest = Never
   smb encrypt = desired
   min protocol = SMB2
   unix extensions = no
   wide links = yes
   follow symlinks = yes
   force user = root
   force group = root
   create mask = 0664
   directory mask = 0775
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

[OmniDrive]
   path = ${ROOT_DIR}
   browseable = yes
   writable = yes
   guest ok = no
EOF

    # Vòng lặp 1: Thêm các share từ options.json
    for (( i=0; i<SHARES_COUNT; i++ )); do
        SHARE_NAME=$(jq -r ".shares[$i].name" "$CONFIG_PATH")
        SHARE_PATH=$(jq -r ".shares[$i].path" "$CONFIG_PATH")
        READ_ONLY=$(jq -r ".shares[$i].read_only" "$CONFIG_PATH")
        WRITABLE="yes"
        [ "$READ_ONLY" = "true" ] && WRITABLE="no"
        cat <<EOF >> /etc/samba/smb.conf

[${SHARE_NAME}]
   path = ${SHARE_PATH}
   browseable = yes
   writable = ${WRITABLE}
   guest ok = no
   force user = root
   force group = root
EOF
    done

    # Vòng lặp 2: Tự động thêm các thư mục trong /mnt/* vào SMB Share
    for dir in /mnt/*; do
        if [ -d "$dir" ]; then
            MNT_NAME=$(basename "$dir")
            if ! grep -q "^\[${MNT_NAME}\]" /etc/samba/smb.conf; then
                cat <<EOF >> /etc/samba/smb.conf

[${MNT_NAME}]
   path = ${dir}
   browseable = yes
   writable = yes
   guest ok = no
   force user = root
   force group = root
EOF
            fi
        fi
    done

    smbd --foreground --no-process-group </dev/null >/dev/null 2>&1 &
    log_info "Protocol [SMB/Samba] active on port 445 (iOS Files, macOS Finder, Windows Explorer)"
fi
