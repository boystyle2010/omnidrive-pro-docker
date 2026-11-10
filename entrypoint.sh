#!/usr/bin/env bash
set -e

# Hàm hiển thị Log thay thế cho bashio::log
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

mkdir -p "$WPRO_DATA" /backup /storage /ssl
touch "$WPRO_DATA/audit.jsonl"
[ ! -f "$WPRO_DATA/shares.json" ] && echo "{}" > "$WPRO_DATA/shares.json"

# Tự động tạo /data/options.json từ Biến môi trường (ENV) nếu chưa tồn tại
if [ ! -f "$CONFIG_PATH" ]; then
    log_info "Generating default configuration at ${CONFIG_PATH} from environment variables..."
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
    {
      "name": "storage",
      "path": "/storage",
      "read_only": false,
      "allowed_users": []
    },
    {
      "name": "backup",
      "path": "/backup",
      "read_only": false,
      "allowed_users": []
    }
  ]
}
EOF
fi

cfg_val() {
    jq -r "$1" "$CONFIG_PATH"
}

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

# ... (giữ nguyên phần đọc biến cfg_val) ...

# 2. Chuẩn bị thư mục gốc hợp nhất (/var/webdav_root) + Tự động nhận diện /mnt/*
mkdir -p "$ROOT_DIR" /mnt
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

# 2B. Tự động phát hiện và gắn bất kỳ thư mục nào người dùng mount vào /mnt/<tên_thư_mục>
for dir in /mnt/*; do
    if [ -d "$dir" ]; then
        MNT_NAME=$(basename "$dir")
        if [ ! -e "${ROOT_DIR}/${MNT_NAME}" ]; then
            ln -sfn "$dir" "${ROOT_DIR}/${MNT_NAME}"
            log_info "Auto-mounted custom volume: /mnt/${MNT_NAME} -> /${MNT_NAME}"
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

    for (( i=0; i<SHARES_COUNT; i++ )); do
        SHARE_NAME=$(jq -r ".shares[$i].name" "$CONFIG_PATH")
        SHARE_PATH=$(jq -r ".shares[$i].path" "$CONFIG_PATH")
        READ_ONLY=$(jq -r ".shares[$i].read_only" "$CONFIG_PATH")
        WRITABLE="yes"
        [ "$READ_ONLY" = "true" ] && WRITABLE="no"
        cat <<EOF >> /etc/samba/smb.conf

# Tự động thêm các thư mục trong /mnt/* vào danh sách SMB Share
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

# 5. Khởi động SFTP / OpenSSH Server (Port 2222)
if is_true "$SFTP_ENABLED"; then
    ssh-keygen -A >/dev/null 2>&1
    mkdir -p /run/sshd
    cat <<EOF > /etc/ssh/sshd_config
Port 2222
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
Subsystem sftp internal-sftp
AllowTcpForwarding no
X11Forwarding no
ForceCommand internal-sftp -d ${ROOT_DIR}
EOF
    /usr/sbin/sshd -D -e >/dev/null 2>&1 &
    log_info "Protocol [SFTP] active on port 2222 (SSH File Transfer)"
fi

# 6. Khởi động FTP / vsftpd Server (Port 2121, Passive 21000-21002)
if is_true "$FTP_ENABLED"; then
    mkdir -p /var/run/vsftpd/empty
    cat <<EOF > /etc/vsftpd/vsftpd.conf
listen=YES
listen_ipv6=NO
listen_port=2121
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
local_root=${ROOT_DIR}
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=21000
pasv_max_port=21002
seccomp_sandbox=NO
EOF
    if [ -n "$PASV_ADDRESS" ]; then
        echo "pasv_address=${PASV_ADDRESS}" >> /etc/vsftpd/vsftpd.conf
    fi
    vsftpd /etc/vsftpd/vsftpd.conf >/dev/null 2>&1 &
    log_info "Protocol [FTP] active on port 2121 (Passive ports: 21000-21002)"
fi

# 7. Cấu hình SSL/TLS cho WebDAV & Web UI
LISTEN_DIRECTIVE="listen ${WEBDAV_PORT};"
SSL_DIRECTIVES=""
if is_true "$SSL"; then
    if [ ! -f "/ssl/${CERTFILE}" ] || [ ! -f "/ssl/${KEYFILE}" ]; then
        exit_nok "SSL certificate not found at /ssl/${CERTFILE} or /ssl/${KEYFILE}"
    fi
    LISTEN_DIRECTIVE="listen ${WEBDAV_PORT} ssl;"
    SSL_DIRECTIVES="
        ssl_certificate /ssl/${CERTFILE};
        ssl_certificate_key /ssl/${KEYFILE};
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
    "
    log_info "Security mode: HTTPS (SSL/TLS) enabled."
else
    log_info "Connection mode: standard HTTP (compatible with Cloudflare Tunnel / Reverse Proxy)."
fi

# 8. Cấu hình hiển thị File Browser (FancyIndex vs AutoIndex)
DOTFILES_RULE=""
if ! is_true "$SHOW_DOTFILES"; then
    DOTFILES_RULE="location ~ /\. { deny all; }"
fi

if is_true "$FANCY_UI"; then
    INDEX_CONFIG="
        fancyindex on;
        fancyindex_exact_size off;
        fancyindex_localtime on;
        fancyindex_header \"/.fancyindex/header.html\";
        fancyindex_footer \"/.fancyindex/footer.html\";
        fancyindex_ignore \"fancyindex\";
    "
else
    INDEX_CONFIG="
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    "
fi

git config --system --add safe.directory '*' || true

# 9. Tạo Python Backend API + Hybrid Auth Engine
cat << 'PYEOF' > /usr/local/bin/wpro_api.py
#!/usr/bin/env python3
import os, sys, json, time, hmac, hashlib, base64, shutil, secrets, tempfile, subprocess, urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http.cookies import SimpleCookie
from datetime import datetime

ROOT_DIR = "/var/webdav_root"
DATA_DIR = "/data/wpro"
CONFIG_PATH = "/data/options.json"
SHARES_FILE = os.path.join(DATA_DIR, "shares.json")
AUDIT_FILE = os.path.join(DATA_DIR, "audit.jsonl")
SECRET_FILE = os.path.join(DATA_DIR, "session.secret")

if not os.path.exists(SECRET_FILE):
    with open(SECRET_FILE, "w") as f:
        f.write(secrets.token_hex(32))
with open(SECRET_FILE, "r") as f:
    SESSION_SECRET = f.read().strip().encode("utf-8")

def get_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def verify_credentials(username, password):
    cfg = get_config()
    for u in cfg.get("users", []):
        if u.get("username") == username and u.get("password") == password:
            return True
    return False

def create_session_token(username, ttl=2592000):
    exp = int(time.time()) + ttl
    payload = f"{username}|{exp}"
    sig = hmac.new(SESSION_SECRET, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(f"{payload}|{sig}".encode("utf-8")).decode("utf-8")

def verify_session_token(token):
    try:
        raw = base64.urlsafe_b64decode(token.encode("utf-8")).decode("utf-8")
        username, exp_str, sig = raw.split("|", 2)
        if int(exp_str) < time.time():
            return None
        expected = hmac.new(SESSION_SECRET, f"{username}|{exp_str}".encode("utf-8"), hashlib.sha256).hexdigest()
        if hmac.compare_digest(sig, expected):
            return username
    except Exception:
        pass
    return None

def load_shares():
    try:
        with open(SHARES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        now = time.time()
        cleaned = {k: v for k, v in data.items() if v.get("exp", 0) > now}
        if len(cleaned) != len(data):
            save_shares(cleaned)
        return cleaned
    except Exception:
        return {}

def save_shares(data):
    with open(SHARES_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def append_audit(user, method, path, status=200, ip="local"):
    entry = {
        "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "user": user or "web",
        "method": method,
        "path": urllib.parse.unquote(path),
        "status": status,
        "ip": ip
    }
    try:
        with open(AUDIT_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass

def safe_resolve(rel_path):
    clean = urllib.parse.unquote(rel_path or "/").lstrip("/")
    full = os.path.normpath(os.path.join(ROOT_DIR, clean))
    if not full.startswith(ROOT_DIR):
        raise ValueError("Invalid path")
    return full

def dir_size_du(path):
    try:
        out = subprocess.check_output(["du", "-sk", path], stderr=subprocess.DEVNULL, timeout=8).decode()
        return int(out.split()[0]) * 1024
    except Exception:
        return 0

class WProHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def get_auth_user(self):
        cookie_hdr = self.headers.get("Cookie", "")
        if cookie_hdr:
            c = SimpleCookie()
            try:
                c.load(cookie_hdr)
                if "wpro_sess" in c:
                    u = verify_session_token(c["wpro_sess"].value)
                    if u:
                        return u
            except Exception:
                pass
        auth_hdr = self.headers.get("Authorization", "")
        if auth_hdr.startswith("Basic "):
            try:
                decoded = base64.b64decode(auth_hdr[6:].strip()).decode("utf-8")
                uname, upass = decoded.split(":", 1)
                if verify_credentials(uname, upass):
                    return uname
            except Exception:
                pass
        return None

    def send_json(self, payload, code=200, extra_headers=None):
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        if route == "/__wpro_api/auth_check":
            user = self.get_auth_user()
            if user:
                self.send_response(200)
                self.send_header("X-WPro-User", user)
                self.end_headers()
            else:
                self.send_response(401)
                self.end_headers()
            return

        if route == "/__wpro_api/protocols":
            cfg = get_config()
            users = cfg.get("users", [])
            first_user = users[0].get("username", "admin") if users else "admin"
            shares = [s.get("name") for s in cfg.get("shares", [])]
            self.send_json({
                "webdav": True,
                "smb": bool(cfg.get("smb_enabled", True)),
                "sftp": bool(cfg.get("sftp_enabled", True)),
                "ftp": bool(cfg.get("ftp_enabled", True)),
                "default_user": first_user,
                "shares": shares
            })
            return

        if route.startswith("/s/") or route == "/__wpro_api/share_dl":
            token = route.split("/s/")[1].split("/")[0] if route.startswith("/s/") else (qs.get("token", [""])[0])
            shares = load_shares()
            info = shares.get(token)
            if not info or info.get("exp", 0) < time.time():
                self.send_response(404)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"Share link expired or invalid.")
                return
            try:
                target = os.path.realpath(safe_resolve(info["path"]))
                if os.path.isdir(target):
                    folder_name = os.path.basename(target.rstrip("/")) or "archive"
                    tmp_fd, tmp_zip = tempfile.mkstemp(suffix=".zip")
                    os.close(tmp_fd)
                    try:
                        subprocess.run(["zip", "-r", "-q", tmp_zip, ".", "-x", "*.db*", "*.log*"], cwd=target, check=False, timeout=90)
                        fsize = os.path.getsize(tmp_zip)
                        append_audit("share-link", "SHARE_DL", info["path"], 200, self.headers.get("X-Real-IP", self.client_address[0]))
                        self.send_response(200)
                        self.send_header("Content-Type", "application/zip")
                        self.send_header("Content-Disposition", f'attachment; filename="{folder_name}.zip"')
                        self.send_header("Content-Length", str(fsize))
                        self.end_headers()
                        with open(tmp_zip, "rb") as f:
                            shutil.copyfileobj(f, self.wfile)
                    finally:
                        if os.path.exists(tmp_zip):
                            os.remove(tmp_zip)
                    return
                elif os.path.isfile(target):
                    fname = os.path.basename(target)
                    fsize = os.path.getsize(target)
                    append_audit("share-link", "SHARE_DL", info["path"], 200, self.headers.get("X-Real-IP", self.client_address[0]))
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
                    self.send_header("Content-Length", str(fsize))
                    self.end_headers()
                    with open(target, "rb") as f:
                        shutil.copyfileobj(f, self.wfile)
                    return
                else:
                    raise FileNotFoundError()
            except Exception:
                self.send_response(404)
                self.end_headers()
            return

        if route == "/__wpro_api/disk":
            try:
                total, used, free = shutil.disk_usage(ROOT_DIR)
                folders = []
                for name in sorted(os.listdir(ROOT_DIR)):
                    fpath = os.path.join(ROOT_DIR, name)
                    if os.path.isdir(fpath):
                        real_p = os.path.realpath(fpath)
                        folders.append({"name": name, "bytes": dir_size_du(real_p)})
                self.send_json({"total": total, "used": used, "free": free, "folders": folders})
            except Exception as e:
                self.send_json({"error": str(e)}, 500)
            return

        if route == "/__wpro_api/git_status":
            rel = qs.get("path", ["/"])[0]
            try:
                target = os.path.realpath(safe_resolve(rel))
                if not os.path.isdir(target):
                    target = os.path.dirname(target)
                top = subprocess.check_output(
                    ["git", "-C", target, "rev-parse", "--show-toplevel"],
                    stderr=subprocess.DEVNULL, timeout=4
                ).decode().strip()
                branch = subprocess.check_output(
                    ["git", "-C", target, "rev-parse", "--abbrev-ref", "HEAD"],
                    stderr=subprocess.DEVNULL, timeout=4
                ).decode().strip()
                porcelain = subprocess.check_output(
                    ["git", "-C", target, "status", "--porcelain", "-uall"],
                    stderr=subprocess.DEVNULL, timeout=5
                ).decode()
                rel_from_top = os.path.relpath(target, top)
                prefix = "" if rel_from_top == "." else rel_from_top.rstrip("/") + "/"
                statuses = {}
                for line in porcelain.splitlines():
                    if len(line) < 4:
                        continue
                    st = line[:2]
                    fp = line[3:].strip().strip('"')
                    if " -> " in fp:
                        fp = fp.split(" -> ")[-1].strip('"')
                    if prefix and not fp.startswith(prefix):
                        continue
                    sub = fp[len(prefix):] if prefix else fp
                    first_seg = sub.split("/")[0]
                    if not first_seg:
                        continue
                    kind = "added" if ("?" in st or "A" in st) else "modified"
                    if first_seg not in statuses or kind == "modified":
                        statuses[first_seg] = kind
                self.send_json({"is_git": True, "branch": branch, "statuses": statuses})
            except Exception:
                self.send_json({"is_git": False, "statuses": {}})
            return

        if route == "/__wpro_api/shares":
            shares = load_shares()
            items = [{"token": k, **v} for k, v in shares.items()]
            items.sort(key=lambda x: x.get("created", 0), reverse=True)
            self.send_json({"shares": items})
            return

        if route == "/__wpro_api/audit":
            limit = int(qs.get("limit", ["150"])[0])
            logs = []
            try:
                if os.path.exists(AUDIT_FILE):
                    with open(AUDIT_FILE, "r", encoding="utf-8", errors="ignore") as f:
                        lines = f.readlines()[-limit:]
                    for ln in reversed(lines):
                        ln = ln.strip()
                        if not ln:
                            continue
                        try:
                            obj = json.loads(ln)
                            p_str = obj.get("path", "")
                            m_str = obj.get("method", "")
                            if p_str.startswith("/.fancyindex") or p_str.startswith("/__wpro_api"):
                                continue
                            if m_str == "GET" and p_str.endswith("/"):
                                continue
                            logs.append(obj)
                        except Exception:
                            pass
            except Exception:
                pass
            self.send_json({"logs": logs[:100]})
            return

        self.send_json({"error": "Not found"}, 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        body = self.read_json_body()

        if route == "/__wpro_api/login":
            uname = body.get("username", "").strip()
            upass = body.get("password", "")
            remember = bool(body.get("remember", True))
            ip = self.headers.get("X-Real-IP", self.client_address[0])
            if verify_credentials(uname, upass):
                ttl = 2592000 if remember else 86400
                tok = create_session_token(uname, ttl)
                cookie_val = f"wpro_sess={tok}; Path=/; Max-Age={ttl}; HttpOnly; SameSite=Lax"
                append_audit(uname, "WEB_LOGIN", "/", 200, ip)
                self.send_json({"ok": True, "user": uname}, 200, {"Set-Cookie": cookie_val})
            else:
                append_audit(uname or "unknown", "LOGIN_FAIL", "/", 401, ip)
                self.send_json({"ok": False, "error": "Invalid username or password"}, 401)
            return

        if route == "/__wpro_api/logout":
            cookie_val = "wpro_sess=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"
            self.send_json({"ok": True}, 200, {"Set-Cookie": cookie_val})
            return

        # Tinh chỉnh thông minh cho cả môi trường HASS và Standalone Docker
        if route == "/__wpro_api/snapshot":
            target_mode = body.get("target", "config")
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_link = os.path.join(ROOT_DIR, "backup")
            backup_dir = os.path.realpath(backup_link) if os.path.exists(backup_link) else "/backup"
            os.makedirs(backup_dir, exist_ok=True)
            
            cfg_link = os.path.join(ROOT_DIR, "config")
            cfg_dir = os.path.realpath(cfg_link) if os.path.exists(cfg_link) else ROOT_DIR
            try:
                if target_mode == "automations" and os.path.exists(cfg_link):
                    zip_name = f"quick_automations_{stamp}.zip"
                    zip_path = os.path.join(backup_dir, zip_name)
                    cmd = ["zip", "-r", "-q", zip_path, "automations.yaml", "scripts.yaml", "scenes.yaml", "configuration.yaml", "automations", "packages"]
                    subprocess.run(cmd, cwd=cfg_dir, check=False, timeout=60)
                else:
                    zip_name = f"quick_snapshot_{stamp}.zip"
                    zip_path = os.path.join(backup_dir, zip_name)
                    cmd = ["zip", "-r", "-y", "-q", zip_path, ".", "-x", "backup/*", "*/home-assistant_v2.db*", "*.db*", "*.log*"]
                    subprocess.run(cmd, cwd=cfg_dir, check=False, timeout=120)

                size_kb = round(os.path.getsize(zip_path) / 1024, 1) if os.path.exists(zip_path) else 0
                append_audit("admin", "SNAPSHOT", f"/backup/{zip_name}", 200)
                self.send_json({"ok": True, "filename": zip_name, "path": f"/backup/{zip_name}", "size_kb": size_kb})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/share":
            action = body.get("action", "create")
            shares = load_shares()
            if action == "revoke":
                tok = body.get("token", "")
                shares.pop(tok, None)
                save_shares(shares)
                append_audit("admin", "SHARE_REVOKE", tok, 200)
                self.send_json({"ok": True})
                return

            rel_path = body.get("path", "")
            ttl = int(body.get("ttl", 3600))
            try:
                full = safe_resolve(rel_path)
                if not os.path.exists(full):
                    self.send_json({"ok": False, "error": "Target path does not exist"}, 400)
                    return
                is_dir = os.path.isdir(full)
                base_name = os.path.basename(full.rstrip("/")) or "root"
                display_name = (base_name + ".zip") if is_dir else base_name
                token = secrets.token_urlsafe(10)
                now = int(time.time())
                shares[token] = {
                    "path": rel_path,
                    "name": display_name,
                    "is_dir": is_dir,
                    "created": now,
                    "exp": now + ttl
                }
                save_shares(shares)
                append_audit("admin", "SHARE_CREATE", rel_path, 200)
                self.send_json({"ok": True, "token": token, "exp": now + ttl, "name": display_name, "is_dir": is_dir})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/audit_clear":
            try:
                open(AUDIT_FILE, "w").close()
                append_audit("admin", "AUDIT_CLEAR", "/", 200)
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/exec":
            cmd_str = body.get("cmd", "").strip()
            cwd_rel = body.get("cwd", "/")
            if not cmd_str:
                self.send_json({"output": ""})
                return
            try:
                cwd_full = os.path.realpath(safe_resolve(cwd_rel))
                if not os.path.isdir(cwd_full):
                    cwd_full = ROOT_DIR
                proc = subprocess.run(
                    cmd_str, shell=True, cwd=cwd_full,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    timeout=25, text=True
                )
                append_audit("admin", "TERM_CMD", cmd_str[:80], proc.returncode)
                self.send_json({"output": proc.stdout, "code": proc.returncode})
            except subprocess.TimeoutExpired:
                self.send_json({"output": "Command timed out after 25s.\n", "code": 124})
            except Exception as e:
                self.send_json({"output": f"Error: {e}\n", "code": 1})
            return

        self.send_json({"error": "Unknown endpoint"}, 404)

if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), WProHandler)
    server.serve_forever()
PYEOF
chmod +x /usr/local/bin/wpro_api.py

# 10. Khởi chạy Python API ở chế độ nền
python3 /usr/local/bin/wpro_api.py "${API_PORT}" &
log_info "Started OmniDrive Pro API & Hybrid Auth Engine on 127.0.0.1:${API_PORT}"

# 11. Sinh file cấu hình Nginx chính
cat <<EOF > "$NGINX_CONF"
load_module /usr/lib/nginx/modules/ngx_http_dav_ext_module.so;
load_module /usr/lib/nginx/modules/ngx_http_fancyindex_module.so;

user root;
worker_processes auto;
pid /run/nginx/nginx.pid;
error_log /dev/stderr ${LOG_LEVEL};

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    subrequest_output_buffer_size 512k;

    map \$http_accept \$is_browser_client {
        default 0;
        "~*text/html" 1;
    }
    map \$is_browser_client \$dav_www_auth {
        1 "";
        0 'Basic realm="OmniDrive Pro WebDAV"';
    }

    log_format wpro_audit escape=json '{"time":"\$time_iso8601","user":"\$upstream_http_x_wpro_user","ip":"\$remote_addr","method":"\$request_method","path":"\$uri","status":\$status}';
    map \$request_method \$is_mutating_or_dl {
        default 0;
        PUT     1;
        DELETE  1;
        MKCOL   1;
        COPY    1;
        MOVE    1;
        GET     1;
    }

    access_log /dev/stdout;
    access_log ${WPRO_DATA}/audit.jsonl wpro_audit if=\$is_mutating_or_dl;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    server_tokens off;
    etag off;

    absolute_redirect off;
    port_in_redirect off;
    
    client_max_body_size ${MAX_UPLOAD};
    client_body_temp_path /var/lib/nginx/tmp/client_body;

    dav_ext_lock_zone zone=davlock:10m;
    limit_req_zone \$binary_remote_addr zone=dav_auth_limit:10m rate=20r/s;

    server {
        ${LISTEN_DIRECTIVE}
        ${SSL_DIRECTIVES}
        server_name _;

        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;

        location ^~ /.fancyindex/ {
            alias /usr/share/nginx/fancyindex/;
            access_log off;
        }

        location = /__wpro_api/login {
            limit_req zone=dav_auth_limit burst=15 nodelay;
            proxy_pass http://127.0.0.1:${API_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            access_log off;
        }
        location = /__wpro_api/logout {
            proxy_pass http://127.0.0.1:${API_PORT};
            proxy_set_header Host \$host;
            access_log off;
        }

        location = /__wpro_auth_check {
            internal;
            proxy_pass http://127.0.0.1:${API_PORT}/__wpro_api/auth_check;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header Cookie \$http_cookie;
            proxy_set_header Authorization \$http_authorization;
        }

        location @login_or_basic {
            add_header WWW-Authenticate \$dav_www_auth always;
            if (\$is_browser_client = 1) {
                return 302 /.fancyindex/login.html?rd=\$request_uri;
            }
            return 401 "Authentication required";
        }

        location ^~ /s/ {
            proxy_pass http://127.0.0.1:${API_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        location ^~ /__wpro_api/ {
            auth_request /__wpro_auth_check;
            error_page 401 = @login_or_basic;
            proxy_pass http://127.0.0.1:${API_PORT};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            access_log off;
        }

        ${DOTFILES_RULE}

        location / {
            limit_req zone=dav_auth_limit burst=40 nodelay;
            auth_request /__wpro_auth_check;
            error_page 401 = @login_or_basic;

            root ${ROOT_DIR};
            ${INDEX_CONFIG}

            dav_methods PUT DELETE MKCOL COPY MOVE;
            dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
            dav_ext_lock zone=davlock;
            create_full_put_path on;
            dav_access user:rw group:rw all:r;

            if (-d \$request_filename) {
                rewrite ^(.*[^/])$ \$1/ break;
            }
        }
    }
}
EOF

# 12. Kiểm tra cú pháp Nginx trước khi chạy
log_info "Checking Nginx configuration syntax..."
if ! nginx -t 2>&1; then
    log_error "Invalid Nginx configuration, see the details above."
    cat -n "$NGINX_CONF" >&2
    exit_nok "Stopping container due to an Nginx configuration error."
fi
log_info "Nginx configuration is valid."

log_info "OmniDrive Pro v${APP_VERSION} is ready on port ${WEBDAV_PORT}!"
exec nginx -g "daemon off;"
