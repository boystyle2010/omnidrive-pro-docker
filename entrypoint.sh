#!/usr/bin/env bash
set -e

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

APP_VERSION="${APP_VERSION:-1.0.30}"
log_info "--------------------------------------------------------"
log_info " Initializing OmniDrive Pro v${APP_VERSION} (Standalone Docker)"
log_info "--------------------------------------------------------"

CONFIG_PATH="/data/options.json"
NGINX_CONF="/etc/nginx/nginx.conf"
ROOT_DIR="/var/webdav_root"
WEBDAV_PORT="${WEBDAV_PORT:-8090}"
API_PORT=8098
WPRO_DATA="/data/wpro"

mkdir -p "$WPRO_DATA" /backup /storage /media /share /ssl /mnt
touch "$WPRO_DATA/audit.jsonl"
[ ! -f "$WPRO_DATA/shares.json" ] && echo "{}" > "$WPRO_DATA/shares.json"

# Theo dõi PID các dịch vụ nền để dừng êm khi Docker stop/restart container
SMBD_PID=""
SSHD_PID=""
VSFTPD_PID=""
API_PID=""
NGINX_PID=""

cleanup() {
    log_info "Shutting down OmniDrive Pro services gracefully..."
    [ -n "${NGINX_PID}" ]  && kill -TERM "${NGINX_PID}" 2>/dev/null || true
    [ -n "${API_PID}" ]    && kill -TERM "${API_PID}" 2>/dev/null || true
    [ -n "${SMBD_PID}" ]   && kill -TERM "${SMBD_PID}" 2>/dev/null || true
    [ -n "${SSHD_PID}" ]   && kill -TERM "${SSHD_PID}" 2>/dev/null || true
    [ -n "${VSFTPD_PID}" ] && kill -TERM "${VSFTPD_PID}" 2>/dev/null || true
    wait 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Chạy một dịch vụ nền và tự khởi động lại nếu nó bị dừng/crash (HEALTHCHECK của Docker chỉ kiểm tra tiến trình, không tự khởi động lại).
# Cách dùng: supervise "<tên>" <quiet:0|1> lệnh [tham số...]   -> PID của vòng giám sát nằm trong $SUPERVISE_PID
# quiet=1: output của dịch vụ không đưa ra log thường xuyên mà ghi vào một file tạm; khi dịch vụ dừng, vài dòng cuối
# (ví dụ "500 OOPS: ..." của vsftpd) được in kèm cảnh báo để biết lý do. Cùng một lỗi chỉ in lại khi nội dung thay đổi.
supervise() {
    local name="$1" quiet="$2"; shift 2
    (
        child=""
        out="/tmp/omnidrive-svc-$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_').log"
        last_err=""
        trap '[ -n "$child" ] && kill -TERM "$child" 2>/dev/null; wait 2>/dev/null; exit 0' TERM INT
        delay=2
        while true; do
            started=$(date +%s)
            # quiet: stdin/stdout/stderr đều là file log (mở đọc-ghi). vsftpd ghi lỗi "500 OOPS" vào fd 0 (kênh điều khiển
            # FTP) chứ không phải stderr, nên nếu fd 0 là /dev/null thì lý do dừng bị mất.
            if [ "$quiet" = "1" ]; then : > "$out"; "$@" 0<>"$out" 1>&0 2>&0 & else "$@" </dev/null & fi
            child=$!
            rc=0; wait "$child" || rc=$?
            child=""
            # Crash ngay sau khi khởi động -> tăng dần thời gian chờ (tối đa 60s) để không spam log
            if [ $(( $(date +%s) - started )) -lt 30 ]; then delay=$(( delay * 2 )); [ "$delay" -gt 60 ] && delay=60; else delay=2; fi
            err=""
            [ "$quiet" = "1" ] && [ -s "$out" ] && err=$(tail -n 5 "$out" | tr -d '\r')
            if [ -n "$err" ] && [ "$err" != "$last_err" ]; then
                log_warn "${name} stopped (exit code ${rc}); restarting in ${delay}s. Last output:"
                printf '%s\n' "$err" | sed 's/^/          | /'
                last_err="$err"
            else
                log_warn "${name} stopped (exit code ${rc}); restarting in ${delay}s..."
            fi
            sleep "$delay" & wait $!
        done
    ) &
    SUPERVISE_PID=$!
}

# Tự động tạo /data/options.json nếu chưa tồn tại, hoặc đồng bộ biến môi trường mỗi lần khởi động
if [ ! -f "$CONFIG_PATH" ]; then
    log_info "Generating default configuration at ${CONFIG_PATH}..."
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
  "users": [],
  "shares": [
    { "name": "storage", "path": "/storage", "read_only": false, "allowed_users": [] },
    { "name": "media",   "path": "/media",   "read_only": false, "allowed_users": [] },
    { "name": "share",   "path": "/share",   "read_only": false, "allowed_users": [] },
    { "name": "backup",  "path": "/backup",  "read_only": false, "allowed_users": [] }
  ]
}
EOF
else
    TMP_CFG=$(mktemp)
    jq \
      --arg smb "${SMB_ENABLED:-}" \
      --arg sftp "${SFTP_ENABLED:-}" \
      --arg ftp "${FTP_ENABLED:-}" \
      --arg ssl "${SSL:-}" \
      --arg cert "${CERTFILE:-}" \
      --arg key "${KEYFILE:-}" \
      --arg maxup "${MAX_UPLOAD_SIZE:-}" \
      --arg fancy "${FANCY_UI:-}" \
      --arg dot "${SHOW_DOTFILES:-}" \
      --arg logl "${LOG_LEVEL:-}" \
      '
      (if $smb != "" then .smb_enabled = ($smb | ascii_downcase == "true") else . end) |
      (if $sftp != "" then .sftp_enabled = ($sftp | ascii_downcase == "true") else . end) |
      (if $ftp != "" then .ftp_enabled = ($ftp | ascii_downcase == "true") else . end) |
      (if $ssl != "" then .ssl = ($ssl | ascii_downcase == "true") else . end) |
      (if $cert != "" then .certfile = $cert else . end) |
      (if $key != "" then .keyfile = $key else . end) |
      (if $maxup != "" then .max_upload_size = $maxup else . end) |
      (if $fancy != "" then .fancy_ui = ($fancy | ascii_downcase == "true") else . end) |
      (if $dot != "" then .show_dotfiles = ($dot | ascii_downcase == "true") else . end) |
      (if $logl != "" then .log_level = $logl else . end)
      ' "$CONFIG_PATH" > "$TMP_CFG" && mv "$TMP_CFG" "$CONFIG_PATH"
    log_info "Synced environment variables into ${CONFIG_PATH}."
fi

chmod 600 "$CONFIG_PATH" 2>/dev/null || true

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
PASV_ADDRESS="${FTP_PASV_ADDRESS:-${LAN_IP:-}}"

# 1b. Privilege mode (ROOT_ACCESS=false dùng PUID:PGID; ROOT_ACCESS=true dùng root)
RUN_AS_ROOT_VAL="${ROOT_ACCESS:-${RUN_AS_ROOT:-false}}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
RUN_USER="root"
RUN_GROUP="root"
addgroup -S omnidrive_users 2>/dev/null || true

if ! is_true "$RUN_AS_ROOT_VAL"; then
    [[ "$PUID" =~ ^[0-9]+$ && "$PGID" =~ ^[0-9]+$ ]] || exit_nok "PUID and PGID must be numbers (got PUID=${PUID} PGID=${PGID})."
    { [ "$PUID" -ne 0 ] && [ "$PGID" -ne 0 ]; } || exit_nok "ROOT_ACCESS=false needs a non-zero PUID/PGID."
    RUN_GROUP=$(getent group "$PGID" | cut -d: -f1)
    if [ -z "$RUN_GROUP" ]; then addgroup -g "$PGID" omnidrive >/dev/null 2>&1 || true; RUN_GROUP=omnidrive; fi
    RUN_USER=$(getent passwd "$PUID" | cut -d: -f1)
    if [ -z "$RUN_USER" ]; then
        adduser -D -H -h /var/webdav_root -s /sbin/nologin -u "$PUID" -G "$RUN_GROUP" omnidrive >/dev/null 2>&1 || true
        RUN_USER=omnidrive
    fi
    for _d in /storage /media /share /backup; do
        if [ -d "$_d" ] && [ "$(stat -c %u "$_d" 2>/dev/null)" = "0" ]; then chown "${PUID}:${PGID}" "$_d" 2>/dev/null || true; fi
    done
    chown -R "${PUID}:${PGID}" /var/lib/nginx 2>/dev/null || true
    log_info "Privilege mode: unprivileged (${RUN_USER}:${RUN_GROUP}, uid ${PUID}, gid ${PGID})."
else
    log_warn "Privilege mode: ROOT (ROOT_ACCESS=true) - file operations can touch anything inside the container and every mounted folder."
fi

LOCK_ROOT_VAL="${LOCK_ROOT:-true}"
export RUN_AS_ROOT="$RUN_AS_ROOT_VAL" PUID PGID LOCK_ROOT="$LOCK_ROOT_VAL"
export LAN_IP="${LAN_IP:-${FTP_PASV_ADDRESS:-}}" PUBLIC_URL="${PUBLIC_URL:-}"

# 2. Chuẩn bị thư mục gốc hợp nhất (/var/webdav_root)
mkdir -p "$ROOT_DIR"
find "${ROOT_DIR:?}" -mindepth 1 -maxdepth 1 -type l -delete

SHARES_COUNT=$(jq '.shares | length' "$CONFIG_PATH")
for (( i=0; i<SHARES_COUNT; i++ )); do
    SHARE_NAME=$(jq -r ".shares[$i].name" "$CONFIG_PATH")
    SHARE_PATH=$(jq -r ".shares[$i].path" "$CONFIG_PATH")

    if [ ! -d "$SHARE_PATH" ]; then
        mkdir -p "$SHARE_PATH"
    fi
    ln -sfn "$SHARE_PATH" "${ROOT_DIR}/${SHARE_NAME}"
done

if [ -d "/host_root" ] && [ -n "$(ls -A /host_root 2>/dev/null)" ]; then
    ln -sfn "/host_root" "${ROOT_DIR}/host_system"
    log_info "Full Host Filesystem mounted at: /host_system (Admin only)"
fi

for dir in /mnt/*; do
    if [ -d "$dir" ]; then
        MNT_NAME=$(basename "$dir")
        if [ ! -e "${ROOT_DIR}/${MNT_NAME}" ]; then
            ln -sfn "$dir" "${ROOT_DIR}/${MNT_NAME}"
            log_info "Auto-mounted volume: /mnt/${MNT_NAME} -> /${MNT_NAME} (Admin only unless added to options.json shares)"
        fi
    fi
done

# 3. Accounts provisioning + Role RBAC (admin / user) + PBKDF2/SHA-512 Hashing
if is_true "$SMB_ENABLED"; then
    mkdir -p /var/lib/samba /data/wpro/samba
    chmod 700 /data/wpro/samba
    if [ ! -L /var/lib/samba/private ]; then
        cp -a /var/lib/samba/private/. /data/wpro/samba/ 2>/dev/null || true
        rm -rf /var/lib/samba/private
        ln -s /data/wpro/samba /var/lib/samba/private
    fi
fi

cat << 'USEREOF' > /usr/local/bin/wpro_users.py
#!/usr/bin/env python3
import os, sys, json, hmac, hashlib, secrets, subprocess, re, pwd

CFG = "/data/options.json"
ROOT_DIR = "/var/webdav_root"
ADMIN_USERS_FILE = "/data/wpro/admin_users.txt"
ALL_USERS_FILE = "/data/wpro/all_users.txt"
ITER = 600000
SMB = os.environ.get("SMB_ENABLED_RESOLVED", "true") == "true"
RUN_USER = os.environ.get("RUN_USER_RESOLVED", "root")
PUID = os.environ.get("PUID", "1000")
PGID = os.environ.get("PGID", "1000")

NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.@-]{0,31}$")

# Tài khoản OmniDrive đã tạo ở lần khởi động trước. Bản Docker đổi UID của admin thành PUID (có thể < 1000,
# ví dụ Unraid 99, Synology 1026...), nên các tài khoản này không được coi là tài khoản hệ thống.
try:
    KNOWN_USERS = set(open("/data/wpro/all_users.txt", encoding="utf-8").read().split())
except Exception:
    KNOWN_USERS = set()

def is_system_account(name):
    # root, nginx, sshd, nobody... (UID < 1000 hoặc >= 60000) không bao giờ được dùng làm tài khoản OmniDrive
    if name in KNOWN_USERS:
        return name in ("root", "nobody")
    try:
        uid = pwd.getpwnam(name).pw_uid
        return uid < 1000 or uid >= 60000   # 65534 = nobody (dùng để chạy git an toàn)
    except KeyError:
        return False

def log(msg): print("[INFO] " + msg, flush=True)
def warn(msg): print("[WARN] " + msg, flush=True)

def make_hash(pw):
    salt = secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha512", pw.encode("utf-8"), bytes.fromhex(salt), ITER).hex()
    return "pbkdf2_sha512$%d$%s$%s" % (ITER, salt, h)

def check_hash(stored, pw):
    try:
        algo, it, salt, h = stored.split("$")
        if algo not in ("pbkdf2_sha256", "pbkdf2_sha512"):
            return False
        calc = hashlib.pbkdf2_hmac(algo.split("_")[1], pw.encode("utf-8"), bytes.fromhex(salt), int(it)).hex()
        return hmac.compare_digest(calc, h)
    except Exception:
        return False

def run(args, inp=None):
    return subprocess.run(args, input=inp, capture_output=True, text=True)

def crypt_hash(pw):
    r = run(["openssl", "passwd", "-6", "-stdin"], pw + "\n")
    return r.stdout.strip() if r.returncode == 0 and r.stdout.startswith("$6$") else ""

try:
    with open(CFG, encoding="utf-8") as f:
        cfg = json.load(f)
except Exception as e:
    print("[ERROR] cannot read options.json: %s" % e); sys.exit(1)

users = cfg.get("users") or []

env_user = os.environ.get("OMNI_USER", "").strip()
env_pass = os.environ.get("OMNI_PASS", "")
pass_file = os.environ.get("OMNI_PASS_FILE", "")
if pass_file:
    try:
        env_pass = open(pass_file, encoding="utf-8").read().rstrip("\r\n")
    except Exception as e:
        warn("OMNI_PASS_FILE unreadable: %s" % e)
if not users and not (env_user and env_pass):
    env_user, env_pass = "admin", "changeme_strong_password"
# OMNI_PASS / OMNI_PASS_FILE chỉ được áp dụng khi giá trị THAY ĐỔI so với lần áp dụng trước (so bằng dấu vân tay
# PBKDF2, không lưu mật khẩu). Nhờ vậy mật khẩu đổi trong Web UI không bị biến cũ trong compose ghi đè khi khởi động lại.
ENV_FP_FILE = "/data/wpro/env_pass_fp.json"
def make_fp(pw):
    salt = secrets.token_hex(16)
    return {"salt": salt, "hash": hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), bytes.fromhex(salt), 100000).hex()}
def match_fp(fp, pw):
    try:
        calc = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), bytes.fromhex(fp["salt"]), 100000).hex()
        return hmac.compare_digest(calc, fp["hash"])
    except Exception:
        return False
env_fp_new = None
if env_user and env_pass:
    try:
        st = json.load(open(ENV_FP_FILE, encoding="utf-8"))
    except Exception:
        st = {}
    exists = any(str(u.get("username", "")).strip() == env_user and u.get("password_hash") for u in users)
    if exists and st.get("user") == env_user and match_fp(st.get("fp") or {}, env_pass):
        log("OMNI_PASS has not changed since it was last applied -> keeping the current password of %s "
            "(for example one changed in the Web UI). Set a NEW value in OMNI_PASS only when you want to reset it." % env_user)
    else:
        if users and users[0].get("username") == env_user:
            users[0]["password"] = env_pass
            users[0]["role"] = users[0].get("role") or "admin"
        else:
            users[0:1] = [{"username": env_user, "password": env_pass, "role": "admin"}] if users else [{"username": env_user, "password": env_pass, "role": "admin"}]
        env_fp_new = {"user": env_user, "fp": make_fp(env_pass)}
        log("Applied the password from %s for %s." % ("OMNI_PASS_FILE" if pass_file else "OMNI_PASS", env_user))

plain = {}
out = []
for idx, u in enumerate(users):
    name = str(u.get("username", "")).strip()
    if not NAME_RE.match(name) or name.isdigit():
        warn("Skipping invalid username %r (letters, digits, '_', '.', '-', '@', max 32 characters; must not start with '-' or '@' or be only digits)." % name); continue
    if is_system_account(name):
        warn("Skipping username %r: it is a reserved system account of the container (e.g. root, nginx, sshd). Choose another name." % name); continue
    raw_role = str(u.get("role") or "").strip().lower()
    if raw_role in ("admin", "user"):
        role = raw_role
    else:
        role = "admin" if idx == 0 else "user"

    pw = u.get("password")
    entry = {"username": name, "role": role}
    for k, v in u.items():
        if k not in ("username", "password", "password_hash", "crypt_hash", "role"):
            entry[k] = v
    if pw:
        plain[name] = str(pw)
        old = u.get("password_hash", "")
        if old and check_hash(old, str(pw)):
            entry["password_hash"] = old
            entry["crypt_hash"] = u.get("crypt_hash") or crypt_hash(str(pw))
        else:
            entry["password_hash"] = make_hash(str(pw))
            entry["crypt_hash"] = crypt_hash(str(pw))
    else:
        entry["password_hash"] = u.get("password_hash", "")
        entry["crypt_hash"] = u.get("crypt_hash", "")
        if not entry["password_hash"]:
            warn("User %s has no password: skipped" % name); continue
    out.append(entry)

if not out:
    print("[ERROR] you must define at least one account under 'users' in %s" % CFG); sys.exit(1)

# Từ chối khởi động khi còn mật khẩu mặc định (đã công khai trong tài liệu)
default_users = [e["username"] for e in out if check_hash(e["password_hash"], "changeme_strong_password")]
if default_users:
    print("[ERROR] Account(s) %s still use the DEFAULT password 'changeme_strong_password'. "
          "For your safety OmniDrive Pro will not start with it: set a new OMNI_PASS (or a new 'password' for these users in "
          "/data/options.json) and restart the container." % ", ".join(default_users), flush=True)
    sys.exit(3)

# Đảm bảo luôn có ít nhất 1 admin
if not any(e.get("role") == "admin" for e in out):
    out[0]["role"] = "admin"
    warn("No user had role 'admin'; promoted first user '%s' to admin." % out[0]["username"])

cfg["users"] = out
tmp = CFG + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, CFG)

if env_fp_new:
    with open(ENV_FP_FILE + ".tmp", "w", encoding="utf-8") as f:
        json.dump(env_fp_new, f)
    os.chmod(ENV_FP_FILE + ".tmp", 0o600)
    os.replace(ENV_FP_FILE + ".tmp", ENV_FP_FILE)

admin_names = [e["username"] for e in out if e.get("role") == "admin"]
all_names = [e["username"] for e in out]
with open(ADMIN_USERS_FILE, "w", encoding="utf-8") as f:
    f.write(" ".join(admin_names) + "\n")
os.chmod(ADMIN_USERS_FILE, 0o600)
with open(ALL_USERS_FILE, "w", encoding="utf-8") as f:
    f.write(" ".join(all_names) + "\n")
os.chmod(ALL_USERS_FILE, 0o600)


for e in out:
    name = e["username"]
    is_adm = (e.get("role") == "admin")
    shell = "/bin/bash" if is_adm else "/sbin/nologin"
    grp = "root" if is_adm else "omnidrive_users"
    if run(["id", name]).returncode != 0:
        run(["adduser", "-D", "-H", "-h", ROOT_DIR, "-s", shell, "-G", grp, name])
    else:
        run(["usermod", "-s", shell, "-g", grp, name])

    if is_adm:
        if name in plain:
            r = run(["chpasswd"], "%s:%s\n" % (name, plain[name]))
        elif e.get("crypt_hash"):
            r = run(["chpasswd", "-e"], "%s:%s\n" % (name, e["crypt_hash"]))
        else:
            r = None
        if r is not None and r.returncode != 0:
            warn("Could not set system password of admin %s (SFTP/FTP may fail): %s" % (name, r.stderr.strip()))
        if RUN_USER != "root":
            try:
                lines = open("/etc/passwd").read().splitlines()
                for i, ln in enumerate(lines):
                    f = ln.split(":")
                    if f[0] == name and len(f) >= 4:
                        f[2], f[3] = PUID, PGID
                        lines[i] = ":".join(f)
                open("/etc/passwd", "w").write("\n".join(lines) + "\n")
            except Exception as ex:
                warn("uid/gid rewrite failed for %s: %s" % (name, ex))
    else:
        # Khóa mật khẩu hệ thống cho tài khoản user thường (chỉ dùng Web UI/WebDAV/SMB theo phân quyền)
        run(["passwd", "-l", name])

    if SMB:
        if name in plain:
            run(["smbpasswd", "-a", "-s", name], "%s\n%s\n" % (plain[name], plain[name]))
            run(["smbpasswd", "-e", name])
        elif run(["pdbedit", "-L", "-u", name]).returncode == 0:
            run(["smbpasswd", "-e", name])
        else:
            warn("SMB password of %s is not stored yet. Set a temporary 'password' in options.json and restart." % name)

    log("Provisioned account: %s (role=%s)" % (name, e["role"]))
USEREOF

SMB_ENABLED_RESOLVED="$SMB_ENABLED" RUN_USER_RESOLVED="$RUN_USER" python3 /usr/local/bin/wpro_users.py || exit_nok "Account provisioning failed (see the error above)."

# Tự xoá OMNI_PASS khỏi docker-compose.yml (chỉ khi file compose được mount vào /compose/docker-compose.yml
# hoặc đường dẫn trong OMNI_COMPOSE_FILE). Mật khẩu đã được băm trong /data nên không cần giữ bản rõ trong compose.
cat << 'SCRUBEOF' > /usr/local/bin/wpro_compose_scrub.py
#!/usr/bin/env python3
import os, re, sys
path = os.environ.get("OMNI_COMPOSE_FILE", "").strip() or "/compose/docker-compose.yml"
if not os.path.isfile(path):
    print("[INFO] OMNI_PASS is still set in your compose file (plain text). It is no longer needed: the password is stored "
          "hashed in ./data. Remove it yourself, or mount the compose file to /compose/docker-compose.yml and "
          "OmniDrive Pro removes it automatically.", flush=True)
    sys.exit(0)
LIST = re.compile(r"""^(\s*)-\s*["']?OMNI_PASS=(.*)$""")
MAP = re.compile(r"""^(\s*)["']?OMNI_PASS["']?\s*:(.*)$""")
NOTE = "# OMNI_PASS removed by OmniDrive Pro: the password is stored hashed in ./data (change it in the Web UI > Security)"
try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines(True)
except Exception as e:
    print("[WARN] Could not read %s: %s" % (path, e), flush=True); sys.exit(0)
out, removed, kept = [], 0, 0
for ln in lines:
    body = ln.rstrip("\r\n")
    m = LIST.match(body) or MAP.match(body)
    if not m:
        out.append(ln); continue
    val = m.group(2).strip().strip("'\"")
    # Giữ nguyên: tham chiếu biến (${OMNI_PASS} trong file .env) hoặc khối nhiều dòng (| >) để không làm hỏng YAML
    if "${" in val or val[:1] in ("|", ">"):
        kept += 1; out.append(ln); continue
    out.append(m.group(1) + NOTE + (ln[len(body):] or "\n")); removed += 1
if removed:
    try:
        # Ghi đè tại chỗ (giữ inode/quyền sở hữu) để hoạt động với bind mount một file
        with open(path, "r+", encoding="utf-8") as f:
            f.seek(0); f.write("".join(out)); f.truncate()
        print("[INFO] Removed OMNI_PASS from %s. It takes effect the next time the container is recreated "
              "(docker compose up -d); the running container is not affected." % path, flush=True)
    except Exception as e:
        print("[WARN] Could not update %s (mounted read-only?): %s" % (path, e), flush=True)
if kept:
    print("[INFO] OMNI_PASS in %s refers to another file (e.g. .env) or is a multi-line value: left unchanged, "
          "remove it there yourself." % path, flush=True)
SCRUBEOF
chmod 700 /usr/local/bin/wpro_compose_scrub.py
if [ -n "${OMNI_PASS:-}" ]; then python3 /usr/local/bin/wpro_compose_scrub.py || true; fi

ADMIN_USERS=$(cat /data/wpro/admin_users.txt 2>/dev/null | tr -s ' ' | xargs || true)
ALL_USERS=$(cat /data/wpro/all_users.txt 2>/dev/null | tr -s ' ' | xargs || true)

if is_true "$LOCK_ROOT_VAL"; then
    chmod 0555 "$ROOT_DIR" || true
    log_info "Root lock: ON (nothing can be created directly at Root; use a share / folder)."
else
    chmod 0775 "$ROOT_DIR" || true
fi

# 4. Khởi động SMB / Samba Server (Port 445) - Thực thi valid users & read_only
if is_true "$SMB_ENABLED"; then
    mkdir -p /var/lib/samba/private /var/log/samba /run/samba
    ROOT_WRITABLE="yes"
    is_true "$LOCK_ROOT_VAL" && ROOT_WRITABLE="no"
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
   force user = ${RUN_USER}
   force group = ${RUN_GROUP}
   create mask = 0664
   directory mask = 0775
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

[OmniDrive]
   path = ${ROOT_DIR}
   browseable = yes
   writable = ${ROOT_WRITABLE}
   guest ok = no
   valid users = ${ADMIN_USERS}
EOF

    for (( i=0; i<SHARES_COUNT; i++ )); do
        SHARE_NAME=$(jq -r ".shares[$i].name" "$CONFIG_PATH")
        SHARE_PATH=$(jq -r ".shares[$i].path" "$CONFIG_PATH")
        READ_ONLY=$(jq -r ".shares[$i].read_only" "$CONFIG_PATH")
        ALLOWED_STR=$(jq -r "(.shares[$i].allowed_users // []) | map(select(. != null and . != \"\")) | join(\" \")" "$CONFIG_PATH")
        WRITABLE="yes"
        [ "$READ_ONLY" = "true" ] && WRITABLE="no"
        if [ -n "$ALLOWED_STR" ]; then
            VALID_USERS=$(printf '%s %s\n' "$ADMIN_USERS" "$ALLOWED_STR" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ' | xargs)
        else
            VALID_USERS="$ALL_USERS"
        fi
        cat <<EOF >> /etc/samba/smb.conf

[${SHARE_NAME}]
   path = ${SHARE_PATH}
   browseable = yes
   writable = ${WRITABLE}
   guest ok = no
   valid users = ${VALID_USERS}
   force user = ${RUN_USER}
   force group = ${RUN_GROUP}
EOF
    done

    if [ -d "/host_root" ] && [ -n "$(ls -A /host_root 2>/dev/null)" ]; then
        cat <<EOF >> /etc/samba/smb.conf

[host_system]
   path = /host_root
   browseable = yes
   writable = yes
   guest ok = no
   valid users = ${ADMIN_USERS}
   force user = ${RUN_USER}
   force group = ${RUN_GROUP}
EOF
    fi

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
   valid users = ${ADMIN_USERS}
   force user = ${RUN_USER}
   force group = ${RUN_GROUP}
EOF
            fi
        fi
    done

    supervise "Samba (smbd)" 1 smbd --foreground --no-process-group
    SMBD_PID=$SUPERVISE_PID
    log_info "Protocol [SMB/Samba] active on port 445 (RBAC valid users enforced)"
fi

# 5. Khởi động SFTP / OpenSSH Server (Port 2222) - Chỉ cho phép Admin
if is_true "$SFTP_ENABLED"; then
    ssh-keygen -A >/dev/null 2>&1
    mkdir -p /run/sshd
    cat <<EOF > /etc/ssh/sshd_config
Port 2222
Protocol 2
PermitRootLogin no
AllowUsers ${ADMIN_USERS}
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
Subsystem sftp internal-sftp
AllowTcpForwarding no
X11Forwarding no
ForceCommand internal-sftp -d ${ROOT_DIR}
EOF
    supervise "SFTP (sshd)" 1 /usr/sbin/sshd -D -e
    SSHD_PID=$SUPERVISE_PID
    log_info "Protocol [SFTP] active on port 2222 (Admin only: ${ADMIN_USERS})"
fi

# 6. Khởi động FTP / vsftpd Server (Port 2121) - Sửa lỗi symlink với chroot_local_user=NO & giới hạn Admin
if is_true "$FTP_ENABLED"; then
    mkdir -p /var/run/vsftpd/empty /etc/vsftpd
    printf '%s\n' ${ADMIN_USERS} > /etc/vsftpd/allowed_users
    chmod 600 /etc/vsftpd/allowed_users
    cat <<EOF > /etc/vsftpd/vsftpd.conf
listen=YES
listen_ipv6=NO
listen_port=2121
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
local_root=${ROOT_DIR}
chroot_local_user=NO
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd/allowed_users
pasv_enable=YES
pasv_min_port=21000
pasv_max_port=21002
seccomp_sandbox=NO
EOF
    if [ -n "$PASV_ADDRESS" ]; then
        echo "pasv_address=${PASV_ADDRESS}" >> /etc/vsftpd/vsftpd.conf
    fi
    FTP_TLS_MODE=$(echo "${FTP_TLS:-optional}" | tr 'A-Z' 'a-z')
    case "$FTP_TLS_MODE" in optional|required|off) ;; *) exit_nok "FTP_TLS must be optional, required or off (got '${FTP_TLS}')." ;; esac
    if [ "$FTP_TLS_MODE" != "off" ]; then
        FTP_CRT=""; FTP_KEY=""
        if [ -f "/ssl/${CERTFILE}" ] && [ -f "/ssl/${KEYFILE}" ]; then
            FTP_CRT="/ssl/${CERTFILE}"; FTP_KEY="/ssl/${KEYFILE}"
        else
            FTP_CRT="/data/wpro/ftp-cert.pem"; FTP_KEY="/data/wpro/ftp-key.pem"
            if [ ! -s "$FTP_CRT" ] || [ ! -s "$FTP_KEY" ]; then
                openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=omnidrive-pro" \
                    -keyout "$FTP_KEY" -out "$FTP_CRT" >/dev/null 2>&1 || true
                chmod 600 "$FTP_KEY" 2>/dev/null || true
            fi
        fi
        if [ -s "$FTP_CRT" ] && [ -s "$FTP_KEY" ]; then
            FORCE="NO"; [ "$FTP_TLS_MODE" = "required" ] && FORCE="YES"
            cat <<EOF >> /etc/vsftpd/vsftpd.conf
ssl_enable=YES
rsa_cert_file=${FTP_CRT}
rsa_private_key_file=${FTP_KEY}
allow_anon_ssl=NO
force_local_logins_ssl=${FORCE}
force_local_data_ssl=${FORCE}
ssl_sslv2=NO
ssl_sslv3=NO
ssl_tlsv1=NO
ssl_ciphers=HIGH
require_ssl_reuse=NO
EOF
            log_info "FTPS (explicit TLS) enabled, mode: ${FTP_TLS_MODE} (Admin only: ${ADMIN_USERS})."
        elif [ "$FTP_TLS_MODE" = "required" ]; then
            exit_nok "FTP_TLS=required but no TLS certificate could be created."
        else
            log_warn "Could not create an FTPS certificate: FTP stays unencrypted."
        fi
    else
        log_warn "FTP_TLS=off: FTP passwords and files are sent in clear text."
    fi
    supervise "FTP (vsftpd)" 1 vsftpd /etc/vsftpd/vsftpd.conf
    VSFTPD_PID=$SUPERVISE_PID
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
FANCY_DOT=""
if ! is_true "$SHOW_DOTFILES"; then
    DOTFILES_RULE="location ~ /\. { deny all; }"
else
    FANCY_DOT="fancyindex_show_dotfiles on;"
fi

if is_true "$FANCY_UI"; then
    INDEX_CONFIG="
        fancyindex on;
        fancyindex_exact_size off;
        fancyindex_localtime on;
        fancyindex_header \"/.fancyindex/header.html\";
        fancyindex_footer \"/.fancyindex/footer.html\";
        fancyindex_ignore \"fancyindex\";
        ${FANCY_DOT}
    "
else
    INDEX_CONFIG="
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    "
fi

# 8b. Root lock cho WebDAV / Web UI
ROOT_LOCK_RULES=""
if is_true "$LOCK_ROOT_VAL"; then
    ROOT_LOCK_RULES=$(cat <<'LOCKEOF'
            set $wpro_rl "";
            if ($request_method ~ "^(PUT|MKCOL|DELETE|MOVE)$") { set $wpro_rl "m"; }
            if ($uri ~ "^/[^/]+/?$") { set $wpro_rl "${wpro_rl}u"; }
            if ($wpro_rl = "mu") { return 403 "Blocked: files and folders cannot be created, renamed or deleted directly at Root. Open a folder first."; }
            set $wpro_rd "";
            if ($request_method ~ "^(COPY|MOVE)$") { set $wpro_rd "m"; }
            if ($http_destination ~ "^(https?://[^/]+)?/[^/]+/?$") { set $wpro_rd "${wpro_rd}d"; }
            if ($wpro_rd = "md") { return 403 "Blocked: the destination is directly at Root. Choose a folder."; }
LOCKEOF
)
fi

git config --system --add safe.directory '*' || true

# 9. Python Backend API (RBAC Hardened + Share-Boundary Isolation)
cat << 'PYEOF' > /usr/local/bin/wpro_api.py
#!/usr/bin/env python3
import os, sys, json, time, hmac, hashlib, base64, shutil, secrets, tempfile, subprocess, threading, html, urllib.parse, posixpath
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http.cookies import SimpleCookie
from datetime import datetime

ROOT_DIR = "/var/webdav_root"
DATA_DIR = "/data/wpro"
CONFIG_PATH = "/data/options.json"
SHARES_FILE = os.path.join(DATA_DIR, "shares.json")
AUDIT_FILE = os.path.join(DATA_DIR, "audit.jsonl")
SECRET_FILE = os.path.join(DATA_DIR, "session.secret")
SESSIONS_FILE = os.path.join(DATA_DIR, "sessions.json")
DEVICES_FILE = os.path.join(DATA_DIR, "known_devices.json")

if not os.path.exists(SECRET_FILE):
    with open(SECRET_FILE, "w") as f:
        f.write(secrets.token_hex(32))
try: os.chmod(SECRET_FILE, 0o600)
except Exception: pass
with open(SECRET_FILE, "r") as f:
    SESSION_SECRET = f.read().strip().encode("utf-8")

def get_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def get_user_role(username):
    users = get_config().get("users", [])
    for idx, u in enumerate(users):
        if u.get("username") == username:
            r = str(u.get("role") or "").strip().lower()
            if r in ("admin", "user"): return r
            return "admin" if idx == 0 else "user"
    return "user"

def is_admin(username):
    return bool(username) and get_user_role(username) == "admin"

def get_share_map():
    m = {}
    for s in get_config().get("shares", []):
        name = str(s.get("name", "")).strip()
        if not name: continue
        allowed = [str(x).strip() for x in (s.get("allowed_users") or []) if x and str(x).strip()]
        m[name] = {
            "name": name,
            "path": os.path.realpath(str(s.get("path", ""))),
            "read_only": bool(s.get("read_only", False)),
            "allowed_users": allowed,
            "admin_only": False,
        }
    # /host_system luôn là admin_only
    if os.path.exists(os.path.join(ROOT_DIR, "host_system")):
        m["host_system"] = {
            "name": "host_system",
            "path": os.path.realpath("/host_root"),
            "read_only": False,
            "allowed_users": [],
            "admin_only": True,
        }
    # Các volume tự động gắn trong /mnt/* mặc định là admin_only nếu chưa khai báo trong options.json shares
    if os.path.isdir("/mnt"):
        for d in sorted(os.listdir("/mnt")):
            full_mnt = os.path.join("/mnt", d)
            if os.path.isdir(full_mnt) and d not in m:
                m[d] = {
                    "name": d,
                    "path": os.path.realpath(full_mnt),
                    "read_only": False,
                    "allowed_users": [],
                    "admin_only": True,
                }
    return m

def user_can_access_share(username, share_name, write=False):
    smap = get_share_map()
    info = smap.get(share_name)
    if not info:
        return False
    if write and info["read_only"]:
        return False
    if is_admin(username):
        return True
    if info.get("admin_only"):
        return False
    allowed = info["allowed_users"]
    if not allowed:
        return True
    return username in allowed

def user_allowed_shares(username):
    smap = get_share_map()
    return [name for name in smap if user_can_access_share(username, name, write=False)]

def norm_req_path(raw):
    # Chuẩn hóa đường dẫn y như Nginx (decode %XX, gộp '//', xử lý '.' và '..') để kiểm tra quyền
    # trên đúng đường dẫn mà Nginx sẽ phục vụ (chống bypass kiểu /media/../config/...)
    p = urllib.parse.unquote(str(raw or "/").split("?", 1)[0].split("#", 1)[0])
    return posixpath.normpath("/" + p.lstrip("/"))

def safe_resolve(rel_path):
    clean = urllib.parse.unquote(rel_path or "/").lstrip("/")
    full = os.path.normpath(os.path.join(ROOT_DIR, clean))
    if full != ROOT_DIR and not full.startswith(ROOT_DIR + os.sep):
        raise ValueError("Invalid path")
    return full

def verify_user_path(username, rel_path, write=False):
    full = safe_resolve(rel_path)
    if full == ROOT_DIR:
        if write:
            raise PermissionError("Cannot modify root directory")
        return full
    rel = full[len(ROOT_DIR):].lstrip(os.sep)
    share_name = rel.split(os.sep, 1)[0]
    if not user_can_access_share(username, share_name, write=write):
        raise PermissionError("Access denied to share '%s'" % share_name)
    smap = get_share_map()
    share_real = smap[share_name]["path"]
    real = os.path.realpath(full)
    if share_real != "/" and real != share_real and not real.startswith(share_real + os.sep):
        raise PermissionError("Path escapes allowed share boundary")
    return full

PW_CACHE = {}
PW_CACHE_KEY = secrets.token_bytes(32)
PW_CACHE_TTL = 300
PW_CACHE_LOCK = threading.Lock()
_DUMMY_HASH = "pbkdf2_sha512$600000$" + "00" * 16 + "$" + "00" * 64

PBKDF2_SEM = threading.BoundedSemaphore(2)

def _pbkdf2_check(stored, password):
    # Giới hạn số phép băm chạy đồng thời: tránh làm treo CPU khi bị dò mật khẩu hàng loạt
    with PBKDF2_SEM:
        return _pbkdf2_check_raw(stored, password)

def _pbkdf2_check_raw(stored, password):
    try:
        algo, it, salt, h = stored.split("$")
        if algo not in ("pbkdf2_sha256", "pbkdf2_sha512"): return False
        it = max(1, min(int(it), 5000000))
        calc = hashlib.pbkdf2_hmac(algo.split("_")[1], password.encode("utf-8"), bytes.fromhex(salt), it).hex()
        return hmac.compare_digest(calc, h)
    except Exception: return False

def verify_credentials(username, password):
    cfg = get_config()
    found = None
    for u in cfg.get("users", []):
        if hmac.compare_digest(str(u.get("username", "")).encode("utf-8"), str(username).encode("utf-8")):
            found = u
    stored = (found or {}).get("password_hash", "") if found else ""
    legacy = (found or {}).get("password", "") if found else ""
    ck = hmac.new(PW_CACHE_KEY, ("%s\0%s\0%s\0%s" % (username, password, stored, legacy)).encode("utf-8"), hashlib.sha256).hexdigest()
    now = time.time()
    with PW_CACHE_LOCK:
        if found and PW_CACHE.get(ck, 0) > now: return True
    if found and stored: ok = _pbkdf2_check(stored, str(password))
    elif found and legacy: ok = hmac.compare_digest(str(legacy).encode("utf-8"), str(password).encode("utf-8"))
    else:
        _pbkdf2_check(_DUMMY_HASH, str(password)); ok = False
    if ok:
        with PW_CACHE_LOCK:
            if len(PW_CACHE) > 2000:
                for k in [k for k, t in PW_CACHE.items() if t <= now]: PW_CACHE.pop(k, None)
            PW_CACHE[ck] = now + PW_CACHE_TTL
    return ok

LOGIN_FAILS, LOGIN_LOCK, MAX_LOGIN_FAILS, LOGIN_WINDOW = {}, threading.Lock(), 10, 300

def login_locked(key):
    now = time.time()
    with LOGIN_LOCK:
        recent = [t for t in LOGIN_FAILS.get(key, []) if now - t < LOGIN_WINDOW]
        LOGIN_FAILS[key] = recent
        return len(recent) >= MAX_LOGIN_FAILS

def login_failed(key):
    with LOGIN_LOCK: LOGIN_FAILS.setdefault(key, []).append(time.time())

def login_ok(key):
    with LOGIN_LOCK: LOGIN_FAILS.pop(key, None)

TERMINAL_ENABLED = os.environ.get("ENABLE_TERMINAL", "false").strip().lower() in ("true", "1", "yes", "on")
RUN_AS_ROOT = os.environ.get("RUN_AS_ROOT", "false").strip().lower() in ("true", "1", "yes", "on")
LOCK_ROOT = os.environ.get("LOCK_ROOT", "true").strip().lower() in ("true", "1", "yes", "on")
try:
    RUN_UID = int(os.environ.get("PUID", "1000"))
    RUN_GID = int(os.environ.get("PGID", "1000"))
except ValueError:
    RUN_UID, RUN_GID = 1000, 1000

def run_as_kwargs():
    if RUN_AS_ROOT: return {}
    return {"user": RUN_UID, "group": RUN_GID, "extra_groups": []}

SECRET_ENV = ("SUPERVISOR_TOKEN", "HASSIO_TOKEN", "INGRESS_TOKEN", "OMNI_PASS")

def child_env():
    env = {k: v for k, v in os.environ.items() if k not in SECRET_ENV}
    if not RUN_AS_ROOT: env["HOME"] = "/tmp"
    return env

def user_can_read(path):
    if RUN_AS_ROOT: return True
    try: return subprocess.run(["test", "-r", path], timeout=5, **run_as_kwargs()).returncode == 0
    except Exception: return False

SHARE_ZIP_MAX = int(os.environ.get("SHARE_ZIP_MAX_MB", "2048")) * 1024 * 1024
SESS_LOCK = threading.RLock()
SESSIONS = {}

def _sess_save():
    try:
        tmp = SESSIONS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(SESSIONS, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, SESSIONS_FILE)
    except Exception: pass

def _sess_load():
    global SESSIONS
    try:
        with open(SESSIONS_FILE, "r", encoding="utf-8") as f: data = json.load(f)
        SESSIONS = {k: v for k, v in data.items() if v.get("exp", 0) > time.time()}
    except Exception: SESSIONS = {}

_sess_load()

def _sess_sign(sid): return hmac.new(SESSION_SECRET, sid.encode("utf-8"), hashlib.sha256).hexdigest()

def _device_fp(user, ua):
    import re as _re
    norm = _re.sub(r"[0-9._]+", "", ua or "")
    return hashlib.sha256((user + "|" + norm).encode("utf-8")).hexdigest()[:20]

def _is_new_device(user, ua):
    fp = _device_fp(user, ua)
    try:
        with open(DEVICES_FILE, "r", encoding="utf-8") as f: known = json.load(f)
    except Exception: known = []
    new = bool(known) and fp not in known
    if fp not in known:
        known = (known + [fp])[-300:]
        try:
            tmp = DEVICES_FILE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f: json.dump(known, f)
            os.chmod(tmp, 0o600)
            os.replace(tmp, DEVICES_FILE)
        except Exception: pass
    return new

def create_session(username, ttl, ip, ua):
    now = int(time.time())
    sid = secrets.token_urlsafe(12)
    with SESS_LOCK:
        for k in [k for k, v in SESSIONS.items() if v.get("exp", 0) <= now]: SESSIONS.pop(k, None)
        SESSIONS[sid] = {"user": username, "created": now, "last_seen": now, "exp": now + ttl,
                         "ip": ip, "last_ip": ip, "ua": (ua or "")[:200], "new": _is_new_device(username, ua)}
        _sess_save()
    return sid + "." + _sess_sign(sid)

def rotate_secret():
    global SESSION_SECRET
    with SESS_LOCK:
        new = secrets.token_hex(32)
        tmp = SECRET_FILE + ".tmp"
        with open(tmp, "w") as f: f.write(new)
        try: os.chmod(tmp, 0o600)
        except Exception: pass
        os.replace(tmp, SECRET_FILE)
        SESSION_SECRET = new.encode("utf-8")
        n = len(SESSIONS); SESSIONS.clear(); _sess_save()
        return n

def user_exists(username):
    return any(u.get("username") == username for u in get_config().get("users", []))

def verify_session_token(token, ip=None):
    try:
        sid, sig = token.rsplit(".", 1)
        if not hmac.compare_digest(sig, _sess_sign(sid)): return None, None
        now = int(time.time())
        with SESS_LOCK:
            sess = SESSIONS.get(sid)
            if not sess or sess.get("exp", 0) < now or not user_exists(sess["user"]): return None, None
            if now - sess.get("last_seen", 0) >= 60 or (ip and ip != sess.get("last_ip")):
                sess["last_seen"] = now
                if ip: sess["last_ip"] = ip
                _sess_save()
            return sess["user"], sid
    except Exception: pass
    return None, None

def revoke_session(sid, only_user=None):
    with SESS_LOCK:
        sess = SESSIONS.get(sid)
        if not sess: return False
        if only_user and sess.get("user") != only_user: return False
        SESSIONS.pop(sid, None)
        _sess_save()
        return True

def revoke_other_sessions(keep_sid, only_user=None):
    with SESS_LOCK:
        gone = [k for k, v in SESSIONS.items() if k != keep_sid and (not only_user or v.get("user") == only_user)]
        for k in gone: SESSIONS.pop(k, None)
        if gone: _sess_save()
        return len(gone)

def list_sessions(current_sid, only_user=None):
    now = int(time.time())
    with SESS_LOCK:
        items = []
        for sid, v in SESSIONS.items():
            if v.get("exp", 0) <= now: continue
            if only_user and v.get("user") != only_user: continue
            items.append({"sid": sid, "user": v.get("user"), "ip": v.get("ip"), "last_ip": v.get("last_ip"),
                          "ua": v.get("ua", ""), "created": v.get("created"), "last_seen": v.get("last_seen"),
                          "exp": v.get("exp"), "current": sid == current_sid,
                          "new": bool(v.get("new")) and (now - v.get("created", 0) < 604800),
                          "ack": bool(v.get("ack"))})
    items.sort(key=lambda x: (not x["current"], -(x["last_seen"] or 0)))
    return items

SHARE_LOCK = threading.RLock()

def load_shares():
    with SHARE_LOCK:
        try:
            with open(SHARES_FILE, "r", encoding="utf-8") as f: data = json.load(f)
            now = time.time()
            def alive(v):
                mu = int(v.get("max_uses", 0) or 0)
                return v.get("exp", 0) > now and (mu == 0 or int(v.get("uses", 0)) < mu)
            cleaned = {k: v for k, v in data.items() if alive(v)}
            if len(cleaned) != len(data): save_shares(cleaned)
            return cleaned
        except Exception: return {}

def save_shares(data):
    with SHARE_LOCK:
        tmp = SHARES_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(data, f, indent=2)
        try: os.chmod(tmp, 0o600)
        except Exception: pass
        os.replace(tmp, SHARES_FILE)

def hash_share_pw(password, salt=None):
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt), 200000).hex()
    return salt, digest

def check_share_pw(info, password):
    salt, expected = info.get("pw_salt"), info.get("pw_hash")
    if not salt or not expected: return True
    return hmac.compare_digest(hash_share_pw(password, salt)[1], expected)

def consume_share_use(token):
    with SHARE_LOCK:
        data = load_shares()
        info = data.get(token)
        if not info: return False
        max_uses = int(info.get("max_uses", 0) or 0)
        uses = int(info.get("uses", 0))
        if max_uses and uses >= max_uses: return False
        info["uses"] = uses + 1
        save_shares(data)
        return True

def content_disposition(fname):
    ascii_name = "".join(c if (32 <= ord(c) < 127 and c not in '"\\;') else "_" for c in fname) or "download"
    return f'attachment; filename="{ascii_name}"; filename*=UTF-8\'\'{urllib.parse.quote(fname)}'

def append_audit(user, method, path, status=200, ip="local"):
    entry = {"time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "user": user or "web", "method": method,
             "path": urllib.parse.unquote(path), "status": status, "ip": ip}
    try:
        with open(AUDIT_FILE, "a", encoding="utf-8") as f: f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception: pass

def perm_target(username, rel):
    import stat
    full = verify_user_path(username, str(rel or "").rstrip("/"), write=True)
    if full.rstrip("/") == ROOT_DIR.rstrip("/"): raise ValueError("Invalid path")
    st = os.lstat(full)
    if stat.S_ISLNK(st.st_mode):
        raise ValueError("This is a link to a shared folder. Open it and change the items inside instead.")
    return full, st

def perm_info(username, rel):
    import stat, pwd, grp
    full, st = perm_target(username, rel)
    try: owner = pwd.getpwuid(st.st_uid).pw_name
    except KeyError: owner = str(st.st_uid)
    try: group = grp.getgrgid(st.st_gid).gr_name
    except KeyError: group = str(st.st_gid)
    return {"ok": True, "name": os.path.basename(full), "is_dir": stat.S_ISDIR(st.st_mode),
            "mode": "%04o" % stat.S_IMODE(st.st_mode), "symbolic": stat.filemode(st.st_mode)[1:],
            "owner": owner, "group": group, "uid": st.st_uid, "gid": st.st_gid}

def perm_apply(username, rel, mode_str, recursive, scope, owner, group):
    import stat, pwd, grp
    mode_str = str(mode_str or "").strip()
    if not (3 <= len(mode_str) <= 4) or any(c not in "01234567" for c in mode_str):
        raise ValueError("Mode must be 3 or 4 octal digits (e.g. 644 or 0755)")
    mode = int(mode_str, 8)
    uid = gid = -1
    if (owner or group) and not RUN_AS_ROOT:
        raise PermissionError("Changing owner/group requires ROOT_ACCESS=true in docker-compose.yml.")
    try:
        if owner: uid = int(owner) if str(owner).isdigit() else pwd.getpwnam(str(owner)).pw_uid
        if group: gid = int(group) if str(group).isdigit() else grp.getgrnam(str(group)).gr_gid
    except KeyError:
        raise ValueError("Unknown owner or group name")
    full, st = perm_target(username, rel)
    targets = [full]
    recursive = bool(recursive) and stat.S_ISDIR(st.st_mode)
    if recursive:
        for dp, dns, fns in os.walk(full, followlinks=False):
            for n in dns + fns: targets.append(os.path.join(dp, n))
            if len(targets) > 200000: raise ValueError("Too many items (limit 200,000)")
    changed = failed = 0
    for t in targets:
        try:
            lst = os.lstat(t)
            if stat.S_ISLNK(lst.st_mode): continue
            isd = stat.S_ISDIR(lst.st_mode)
            if recursive and ((scope == "files" and isd) or (scope == "dirs" and not isd)): continue
            if uid != -1 or gid != -1: os.chown(t, uid, gid)
            os.chmod(t, mode)
            changed += 1
        except OSError:
            failed += 1
    return {"ok": True, "changed": changed, "failed": failed, "mode": "%04o" % mode}

GIT_HARDEN = ["git", "-c", "safe.directory=*", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
              "-c", "core.untrackedCache=false", "--no-optional-locks"]

def git_out(args, timeout):
    # Không bao giờ chạy git bằng root trên thư mục người dùng kiểm soát: .git/config độc hại
    # (core.fsmonitor, filter.*.clean...) có thể thực thi lệnh. Chạy bằng 'nobody', tắt hook/fsmonitor.
    env = {"PATH": os.environ.get("PATH", "/usr/sbin:/usr/bin:/sbin:/bin"), "HOME": "/tmp",
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"}
    return subprocess.check_output(GIT_HARDEN + args, stderr=subprocess.DEVNULL, timeout=timeout, env=env, cwd="/tmp",
                                   user=65534, group=65534, extra_groups=[]).decode()

def dir_size_du(path):
    try: return int(subprocess.check_output(["du", "-sk", path], stderr=subprocess.DEVNULL, timeout=8).decode().split()[0]) * 1024
    except Exception: return 0

def dir_size_bytes(path):
    try: return int(subprocess.check_output(["du", "-sk", path], stderr=subprocess.DEVNULL, timeout=8).decode().split()[0]) * 1024
    except Exception: return None

CONFIG_LOCK = threading.Lock()

def _make_pw_hash(pw):
    salt = secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha512", pw.encode("utf-8"), bytes.fromhex(salt), 600000).hex()
    return "pbkdf2_sha512$600000$%s$%s" % (salt, h)

def change_user_password(username, new_pw):
    crypt = ""
    try:
        r = subprocess.run(["openssl", "passwd", "-6", "-stdin"], input=new_pw + "\n", capture_output=True, text=True, timeout=20)
        if r.returncode == 0 and r.stdout.startswith("$6$"): crypt = r.stdout.strip()
    except Exception: pass

    user_is_admin = is_admin(username)
    with CONFIG_LOCK:
        cfg = get_config()
        target = None
        for u in cfg.get("users", []):
            if u.get("username") == username: target = u; break
        if target is None: return False, ["user not found"]
        target["password_hash"] = _make_pw_hash(new_pw)
        target["crypt_hash"] = crypt
        target.pop("password", None)
        tmp = CONFIG_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(cfg, f, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, CONFIG_PATH)

    warnings = []
    if user_is_admin:
        try:
            if crypt:
                r = subprocess.run(["chpasswd", "-e"], input="%s:%s\n" % (username, crypt), capture_output=True, text=True, timeout=20)
            else:
                r = subprocess.run(["chpasswd"], input="%s:%s\n" % (username, new_pw), capture_output=True, text=True, timeout=20)
            if r.returncode != 0: warnings.append("SFTP/FTP password could not be updated")
        except Exception: warnings.append("SFTP/FTP password could not be updated")

    if cfg.get("smb_enabled", True):
        try:
            r = subprocess.run(["smbpasswd", "-a", "-s", username], input="%s\n%s\n" % (new_pw, new_pw), capture_output=True, text=True, timeout=20)
            if r.returncode != 0: warnings.append("SMB password could not be updated")
        except Exception: warnings.append("SMB password could not be updated")
    return True, warnings

ZIP_JOBS = {}
ZIP_LOCK = threading.Lock()

def zip_plan(username, raw_paths):
    if not isinstance(raw_paths, list) or not raw_paths: raise ValueError("Nothing selected")
    if len(raw_paths) > 500: raise ValueError("Too many items selected (max 500)")
    parent, names, total = None, [], 0
    for rp in raw_paths:
        try:
            full = verify_user_path(username, str(rp).rstrip("/"), write=False)
        except PermissionError as e:
            raise ValueError(str(e))
        except Exception:
            raise ValueError("Invalid path")
        name = os.path.basename(full)
        par = os.path.dirname(full)
        if not name or full.rstrip("/") == ROOT_DIR.rstrip("/"): raise ValueError("Invalid path")
        if parent is None: parent = par
        elif par != parent: raise ValueError("Select items from a single folder")
        real = os.path.realpath(full)
        if not os.path.exists(real) or not user_can_read(real): raise ValueError("Cannot read: " + name)
        if os.path.isdir(real):
            sz = dir_size_bytes(real)
            if sz is None: raise ValueError("A selected folder is too large to measure")
            total += sz
        else:
            total += os.path.getsize(real)
        if name in names: continue
        names.append(name)
    if total > SHARE_ZIP_MAX:
        raise ValueError("Selection is too large (limit %d MB)" % (SHARE_ZIP_MAX // (1024 * 1024)))
    return parent, names, total

def zip_job_create(user, raw_paths):
    plan = zip_plan(user, raw_paths)
    now = time.time()
    with ZIP_LOCK:
        for k in [k for k, v in ZIP_JOBS.items() if v["exp"] < now]: ZIP_JOBS.pop(k, None)
        tok = secrets.token_urlsafe(18)
        ZIP_JOBS[tok] = {"user": user, "paths": raw_paths, "exp": now + 120}
    return tok, plan

MAX_JSON_BODY = 1024 * 1024

class WProHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): return
    def client_ip(self): return self.headers.get("X-Real-IP", self.client_address[0])

    def get_auth_user(self):
        self.sid = None
        cookie_hdr = self.headers.get("Cookie", "")
        if cookie_hdr:
            c = SimpleCookie()
            try:
                c.load(cookie_hdr)
                if "wpro_sess" in c:
                    u, sid = verify_session_token(c["wpro_sess"].value, self.client_ip())
                    if u: self.sid = sid; return u
            except Exception: pass
        auth_hdr = self.headers.get("Authorization", "")
        if auth_hdr.startswith("Basic "):
            try:
                decoded = base64.b64decode(auth_hdr[6:].strip()).decode("utf-8")
                uname, upass = decoded.split(":", 1)
                ip = self.client_ip()
                lock_key = ip + "|" + uname.lower()
                if login_locked(lock_key): return None
                if verify_credentials(uname, upass):
                    login_ok(lock_key); return uname
                login_failed(lock_key)
            except Exception: pass
        return None

    def send_json(self, payload, code=200, extra_headers=None):
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        if extra_headers:
            for k, v in extra_headers.items(): self.send_header(k, v)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def share_page(self, token, info, error=None, code=200):
        name = html.escape(info.get("name", "file"))
        err = '<p class="err">' + html.escape(error) + '</p>' if error else ""
        page = ("""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1, maximum-scale=1, user-scalable=no"><meta name="color-scheme" content="dark">
<title>Password Requires</title><style>
:root { --bg:#0b1933; --card:rgba(24,28,38,.74); --input:rgba(38,44,58,.82); --text:#fff; --muted:#94a3b8; --blue:#0a84ff; }
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
body { margin:0; min-height:100vh; display:grid; place-items:center; background-color:var(--bg); color:var(--text);
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; padding:20px; position:relative; overflow:hidden; }
.ambient { position:fixed; top:-120px; left:-120px; right:-120px; bottom:-120px; z-index:-1; pointer-events:none;
background: radial-gradient(circle at 50% 8%,rgba(14,165,233,.32),transparent 60%), radial-gradient(circle at 18% 35%,rgba(10,132,255,.28),transparent 58%), radial-gradient(circle at 82% 85%,rgba(139,92,246,.32),transparent 60%), linear-gradient(180deg,#0b1933 0%,#0d1f42 50%,#12163b 100%); }
.card { width:100%; max-width:380px; background:var(--card); -webkit-backdrop-filter:saturate(190%) blur(28px); backdrop-filter:saturate(190%) blur(28px);
border:1px solid rgba(255,255,255,.14); border-radius:26px; padding:30px 24px 26px; box-shadow:0 24px 60px rgba(0,0,0,.65); text-align:center; animation:popIn .32s cubic-bezier(.2,.9,.3,1); }
@keyframes popIn { from{opacity:0;transform:scale(.94) translateY(10px)} to{opacity:1;transform:scale(1) translateY(0)} }
h1 { font-size:20px; margin:0 0 6px; display:flex; align-items:center; justify-content:center; gap:8px; color:#fff; }
h1 svg { width:22px; height:22px; color:#e2e8f0; }
p { color:var(--muted); font-size:14px; margin:0 0 22px; word-break:break-word; }
.input-wrap { position:relative; display:flex; align-items:center; margin-bottom:20px; text-align:left; }
.input-wrap svg { position:absolute; left:13px; width:18px; height:18px; color:var(--muted); pointer-events:none; }
input { width:100%; height:46px; border-radius:13px; border:1px solid rgba(255,255,255,.1); background:var(--input);
color:#fff; font-size:16px; padding:0 16px 0 40px; outline:none; transition:border-color .15s, background .15s; }
input:focus { border-color:var(--blue); background:rgba(48,56,74,.95); }
button { width:100%; height:48px; border:0; border-radius:14px; background:var(--blue); color:#fff; font-size:16px; font-weight:600; cursor:pointer;
box-shadow:0 6px 20px rgba(10,132,255,.38); transition:transform .12s, opacity .15s; display:flex; align-items:center; justify-content:center; }
button:active { transform:scale(.98); }
.err { color:#ff6961; margin:0 0 12px; font-size:13px; }
</style></head><body><div class="ambient"></div><div class="card">
<h1><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg> Password Requires</h1>
<p>""" + name + """</p>""" + err + """
<form method="post" action="">
<div class="input-wrap">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
    <input type="password" name="password" placeholder="Enter Password" autocomplete="off" autofocus required>
</div>
<button type="submit">Download</button>
</form></div></body></html>""").encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def serve_zip_selection(self, user, job):
        try:
            parent, names, total = zip_plan(user, job["paths"])
        except ValueError as e:
            self.share_gone(400, str(e).encode("utf-8")); return
        rel_parent = parent[len(ROOT_DIR):] or "/"
        append_audit(user, "DOWNLOAD_SELECTION", rel_parent + " (" + str(len(names)) + " items)", 200, self.client_ip())
        single = os.path.realpath(os.path.join(parent, names[0])) if len(names) == 1 else None
        if single and os.path.isfile(single):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", content_disposition(names[0]))
            self.send_header("Content-Length", str(os.path.getsize(single)))
            self.end_headers()
            with open(single, "rb") as f: shutil.copyfileobj(f, self.wfile)
            return
        tmpdir = tempfile.mkdtemp()
        try:
            if not RUN_AS_ROOT: os.chown(tmpdir, RUN_UID, RUN_GID)
            tmp_zip = os.path.join(tmpdir, "selection.zip")
            subprocess.run(["zip", "-r", "-y", "-q", "-1", tmp_zip] + ["./" + n for n in names], cwd=parent, check=False, timeout=900, **run_as_kwargs())
            if not os.path.exists(tmp_zip):
                self.share_gone(500, b"Could not create the zip file."); return
            zname = ((os.path.basename(parent) or "files") + "_" + str(len(names)) + "_items.zip")
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", content_disposition(zname))
            self.send_header("Content-Length", str(os.path.getsize(tmp_zip)))
            self.end_headers()
            with open(tmp_zip, "rb") as f: shutil.copyfileobj(f, self.wfile)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def share_gone(self, code=404, text=b"Share link expired or invalid."):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(text)

    def serve_share(self, token, info):
        ip = self.client_ip()
        try:
            owner = info.get("owner") or ""
            full = safe_resolve(info["path"])
            rel = full[len(ROOT_DIR):].lstrip(os.sep)
            share_name = rel.split(os.sep, 1)[0] if rel else ""
            smap = get_share_map()
            if share_name not in smap: raise FileNotFoundError()
            if owner and not user_can_access_share(owner, share_name, write=False): raise PermissionError()
            target = os.path.realpath(full)
            share_real = smap[share_name]["path"]
            if share_real != "/" and target != share_real and not target.startswith(share_real + os.sep): raise PermissionError()

            is_dir = os.path.isdir(target)
            if not (is_dir or os.path.isfile(target)) or not user_can_read(target): raise FileNotFoundError()
            if is_dir:
                dsz = dir_size_bytes(target)
                if dsz is None or dsz > SHARE_ZIP_MAX:
                    self.share_gone(413, b"Folder is too large to download as a zip. Share individual files instead."); return
            if not consume_share_use(token): self.share_gone(); return
            append_audit("share-link", "SHARE_DL", info["path"], 200, ip)
            if is_dir:
                folder_name = os.path.basename(target.rstrip("/")) or "archive"
                tmpdir = tempfile.mkdtemp()
                try:
                    if not RUN_AS_ROOT: os.chown(tmpdir, RUN_UID, RUN_GID)
                    tmp_zip = os.path.join(tmpdir, "share.zip")
                    subprocess.run(["zip", "-r", "-y", "-q", tmp_zip, ".", "-x", "*.db*", "*.log*"], cwd=target, check=False, timeout=90, **run_as_kwargs())
                    fsize = os.path.getsize(tmp_zip)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/zip")
                    self.send_header("Content-Disposition", content_disposition(folder_name + ".zip"))
                    self.send_header("Content-Length", str(fsize))
                    self.end_headers()
                    with open(tmp_zip, "rb") as f: shutil.copyfileobj(f, self.wfile)
                finally: shutil.rmtree(tmpdir, ignore_errors=True)
                return
            fname = os.path.basename(target)
            fsize = os.path.getsize(target)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", content_disposition(fname))
            self.send_header("Content-Length", str(fsize))
            self.end_headers()
            with open(target, "rb") as f: shutil.copyfileobj(f, self.wfile)
        except Exception:
            try: self.share_gone()
            except Exception: pass

    def handle_share_post(self, route):
        token = route.split("/s/")[1].split("/")[0]
        ip = self.client_ip()
        info = load_shares().get(token)
        if not info: self.share_gone(); return
        key = "share|" + token + "|" + ip
        if login_locked(key):
            self.share_page(token, info, "Too many wrong attempts. Try again in a few minutes.", 429); return
        try:
            length = max(0, min(int(self.headers.get("Content-Length", "0")), 4096))
            form = urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", "ignore"))
        except Exception: form = {}
        if not check_share_pw(info, form.get("password", [""])[0]):
            login_failed(key)
            append_audit("share-link", "SHARE_PW_FAIL", info["path"], 403, ip)
            time.sleep(0.4)
            self.share_page(token, info, "Wrong password.", 403); return
        login_ok(key)
        self.serve_share(token, info)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0: return {}
        if length > MAX_JSON_BODY: raise ValueError("Request body too large")
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        return data if isinstance(data, dict) else {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        if route == "/__wpro_api/auth_check":
            user = self.get_auth_user()
            if not user:
                self.send_response(401)
                self.end_headers()
                return
            orig_uri = self.headers.get("X-Original-URI", "/")
            orig_method = self.headers.get("X-Original-Method", "GET").upper()
            orig_path = norm_req_path(orig_uri)
            is_write = orig_method in ("PUT", "DELETE", "MKCOL", "COPY", "MOVE", "LOCK", "UNLOCK", "PATCH")
            # Cho phép đi qua các đường dẫn nội bộ (sẽ kiểm tra quyền chi tiết bên trong từng endpoint)
            if any(orig_path == pre or orig_path.startswith(pre + "/") for pre in ("/__wpro_api", "/.fancyindex", "/s")):
                self.send_response(200)
                self.send_header("X-WPro-User", user)
                self.end_headers()
                return
            stripped = orig_path.lstrip("/")
            if stripped:
                share_name = stripped.split("/", 1)[0]
                if not user_can_access_share(user, share_name, write=is_write):
                    self.send_response(403)
                    self.end_headers()
                    return
                if orig_method in ("COPY", "MOVE"):
                    dest_hdr = self.headers.get("X-Original-Destination", "")
                    if dest_hdr:
                        dest_path = norm_req_path(urllib.parse.urlparse(dest_hdr).path).lstrip("/")
                        dest_share = dest_path.split("/", 1)[0] if dest_path else ""
                        if not dest_share or not user_can_access_share(user, dest_share, write=True):
                            self.send_response(403)
                            self.end_headers()
                            return
            elif is_write and (LOCK_ROOT or not is_admin(user)):
                self.send_response(403)
                self.end_headers()
                return

            self.send_response(200)
            self.send_header("X-WPro-User", user)
            self.end_headers()
            return

        if route == "/__wpro_api/protocols":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            cfg = get_config()
            adm = is_admin(user)
            self.send_json({
                "webdav": True,
                "smb": bool(cfg.get("smb_enabled", True)),
                "sftp": bool(cfg.get("sftp_enabled", True)) and adm,
                "ftp": bool(cfg.get("ftp_enabled", True)) and adm,
                "default_user": user,
                "role": "admin" if adm else "user",
                "shares": user_allowed_shares(user),
                "lan_ip": os.environ.get("LAN_IP", os.environ.get("FTP_PASV_ADDRESS", "")),
                "public_url": os.environ.get("PUBLIC_URL", ""),
                "smb_port": int(os.environ.get("SMB_PORT", "445")),
                "sftp_port": int(os.environ.get("SFTP_PORT", "2222")),
                "ftp_port": int(os.environ.get("FTP_PORT", "2121")),
                "ext_port": int(os.environ.get("EXTERNAL_PORT", "8090")),
                "terminal": TERMINAL_ENABLED and adm,
                "run_as_root": RUN_AS_ROOT and adm
            })
            return

        if route.startswith("/s/") or route == "/__wpro_api/share_dl":
            token = route.split("/s/")[1].split("/")[0] if route.startswith("/s/") else (qs.get("token", [""])[0])
            info = load_shares().get(token)
            if not info or info.get("exp", 0) < time.time(): self.share_gone(); return
            if info.get("pw_hash"): self.share_page(token, info); return
            self.serve_share(token, info); return

        if route == "/__wpro_api/zip_selected":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            with ZIP_LOCK: job = ZIP_JOBS.pop(qs.get("token", [""])[0], None)
            if not job or job["exp"] < time.time() or job["user"] != user:
                self.share_gone(404, b"Download link expired. Select the items again."); return
            self.serve_zip_selection(user, job); return

        if route == "/__wpro_api/sessions":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            only_u = None if is_admin(user) else user
            self.send_json({"sessions": list_sessions(self.sid, only_user=only_u)}); return

        if route == "/__wpro_api/disk":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            try:
                disk_ref = "/host_root" if os.path.exists("/host_root") else ROOT_DIR
                total, used, free = shutil.disk_usage(disk_ref)
                allowed_set = set(user_allowed_shares(user))
                folders = []
                for name in sorted(os.listdir(ROOT_DIR)):
                    if name == "host_system" or name not in allowed_set: continue
                    fpath = os.path.join(ROOT_DIR, name)
                    if os.path.isdir(fpath):
                        real_p = os.path.realpath(fpath)
                        folders.append({"name": name, "bytes": dir_size_du(real_p)})
                self.send_json({"total": total, "used": used, "free": free, "folders": folders})
            except Exception as e: self.send_json({"error": str(e)}, 500)
            return

        if route == "/__wpro_api/perm_info":
            user = self.get_auth_user()
            if not user: self.send_json({"ok": False, "error": "Unauthorized"}, 401); return
            if not is_admin(user): self.send_json({"ok": False, "error": "Admin privileges required"}, 403); return
            try: self.send_json(perm_info(user, qs.get("path", ["/"])[0]))
            except (ValueError, PermissionError, OSError) as e: self.send_json({"ok": False, "error": str(e)}, 400)
            return

        if route == "/__wpro_api/git_status":
            user = self.get_auth_user()
            if not user: self.send_json({"is_git": False, "statuses": {}}, 401); return
            rel = qs.get("path", ["/"])[0]
            try:
                target = os.path.realpath(verify_user_path(user, rel, write=False))
                if not os.path.isdir(target): target = os.path.dirname(target)
                top = git_out(["-C", target, "rev-parse", "--show-toplevel"], 4).strip()
                branch = git_out(["-C", target, "rev-parse", "--abbrev-ref", "HEAD"], 4).strip()
                porcelain = git_out(["-C", target, "status", "--porcelain", "-uall", "--ignore-submodules=all"], 5)
                rel_from_top = os.path.relpath(target, top)
                prefix = "" if rel_from_top == "." else rel_from_top.rstrip("/") + "/"
                statuses = {}
                for line in porcelain.splitlines():
                    if len(line) < 4: continue
                    st = line[:2]; fp = line[3:].strip().strip('"')
                    if " -> " in fp: fp = fp.split(" -> ")[-1].strip('"')
                    if prefix and not fp.startswith(prefix): continue
                    sub = fp[len(prefix):] if prefix else fp
                    first_seg = sub.split("/")[0]
                    if not first_seg: continue
                    kind = "added" if ("?" in st or "A" in st) else "modified"
                    if first_seg not in statuses or kind == "modified": statuses[first_seg] = kind
                self.send_json({"is_git": True, "branch": branch, "statuses": statuses})
            except Exception: self.send_json({"is_git": False, "statuses": {}})
            return

        if route == "/__wpro_api/shares":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            adm = is_admin(user)
            shares = load_shares()
            items = []
            for k, v in shares.items():
                if not adm and v.get("owner") != user: continue
                items.append({"token": k, **{kk: vv for kk, vv in v.items() if kk not in ("pw_hash", "pw_salt")},
                              "has_password": bool(v.get("pw_hash"))})
            items.sort(key=lambda x: x.get("created", 0), reverse=True)
            self.send_json({"shares": items}); return

        if route == "/__wpro_api/audit":
            user = self.get_auth_user()
            if not user: self.send_json({"error": "Unauthorized"}, 401); return
            adm = is_admin(user)
            limit = int(qs.get("limit", ["150"])[0])
            logs = []
            try:
                if os.path.exists(AUDIT_FILE):
                    with open(AUDIT_FILE, "r", encoding="utf-8", errors="ignore") as f: lines = f.readlines()[-limit:]
                    for ln in reversed(lines):
                        ln = ln.strip()
                        if not ln: continue
                        try:
                            obj = json.loads(ln)
                            if not adm and obj.get("user") != user: continue
                            p_str = obj.get("path", ""); m_str = obj.get("method", "")
                            if p_str.startswith("/.fancyindex") or p_str.startswith("/__wpro_api"): continue
                            if m_str == "GET" and p_str.endswith("/"): continue
                            logs.append(obj)
                        except Exception: pass
            except Exception: pass
            self.send_json({"logs": logs[:100]}); return

        self.send_json({"error": "Not found"}, 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        route = parsed.path
        if route.startswith("/s/"): self.handle_share_post(route); return
        if self.headers.get("X-WPro-CSRF") != "1": self.send_json({"ok": False, "error": "Missing CSRF header"}, 403); return
        try:
            body = self.read_json_body()
        except Exception:
            self.close_connection = True
            self.send_json({"ok": False, "error": "Invalid or too large request body"}, 413); return

        if route == "/__wpro_api/login":
            uname = body.get("username", "").strip()
            upass = body.get("password", "")
            remember = bool(body.get("remember", True))
            ip = self.client_ip()
            lock_key = ip + "|" + uname.lower()
            if login_locked(lock_key):
                append_audit(uname or "unknown", "LOGIN_LOCKED", "/", 429, ip)
                self.send_json({"ok": False, "error": "Too many failed attempts. Try again in a few minutes."}, 429); return
            if verify_credentials(uname, upass):
                login_ok(lock_key)
                ttl = 2592000 if remember else 86400
                tok = create_session(uname, ttl, ip, self.headers.get("User-Agent", ""))
                is_https = (self.headers.get("X-Forwarded-Proto", "").lower() == "https"
                            or "https" in self.headers.get("CF-Visitor", "").lower()
                            or bool(get_config().get("ssl")))
                secure = "; Secure" if is_https else ""
                cookie_val = f"wpro_sess={tok}; Path=/; Max-Age={ttl}; HttpOnly; SameSite=Lax{secure}"
                append_audit(uname, "WEB_LOGIN", "/", 200, ip)
                self.send_json({"ok": True, "user": uname, "role": get_user_role(uname)}, 200, {"Set-Cookie": cookie_val})
            else:
                login_failed(lock_key); time.sleep(0.4)
                append_audit(uname or "unknown", "LOGIN_FAIL", "/", 401, ip)
                self.send_json({"ok": False, "error": "Invalid username or password"}, 401)
            return

        if route == "/__wpro_api/logout":
            try:
                c = SimpleCookie(); c.load(self.headers.get("Cookie", ""))
                if "wpro_sess" in c: revoke_session(c["wpro_sess"].value.rsplit(".", 1)[0])
            except Exception: pass
            self.send_json({"ok": True}, 200, {"Set-Cookie": "wpro_sess=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"}); return

        # Mọi route phía dưới bắt buộc xác thực
        user = self.get_auth_user()
        if not user:
            self.send_json({"ok": False, "error": "Unauthorized"}, 401); return
        ip = self.client_ip()
        adm = is_admin(user)

        if route == "/__wpro_api/change_password":
            old_pw, new_pw = str(body.get("old", "")), str(body.get("new", ""))
            key = "chpw|" + ip + "|" + user.lower()
            if login_locked(key): self.send_json({"ok": False, "error": "Too many wrong attempts. Try again in a few minutes."}, 429); return
            if not verify_credentials(user, old_pw):
                login_failed(key); time.sleep(0.4)
                append_audit(user, "PASSWORD_CHANGE_FAIL", "wrong current password", 403, ip)
                self.send_json({"ok": False, "error": "Current password is wrong"}, 403); return
            login_ok(key)
            if len(new_pw) < 8 or len(new_pw) > 128 or any(ord(c) < 32 for c in new_pw):
                self.send_json({"ok": False, "error": "New password must be 8-128 characters with no control characters"}, 400); return
            if new_pw == old_pw: self.send_json({"ok": False, "error": "New password must be different"}, 400); return
            ok, warnings = change_user_password(user, new_pw)
            if not ok: self.send_json({"ok": False, "error": "Could not change the password"}, 500); return
            n = revoke_other_sessions(self.sid, only_user=user)
            append_audit(user, "PASSWORD_CHANGE", "other devices signed out: " + str(n), 200, ip)
            # OMNI_PASS chỉ áp dụng khi giá trị đổi (dấu vân tay) nên không còn ghi đè mật khẩu này; dọn bản rõ khỏi compose
            if os.environ.get("OMNI_PASS"):
                try: subprocess.run(["python3", "/usr/local/bin/wpro_compose_scrub.py"], timeout=15, check=False)
                except Exception: pass
            self.send_json({"ok": True, "revoked": n, "env_override": False, "warnings": warnings}); return

        if route == "/__wpro_api/zip_prepare":
            try:
                tok, plan = zip_job_create(user, body.get("paths"))
            except ValueError as e:
                self.send_json({"ok": False, "error": str(e)}, 400); return
            self.send_json({"ok": True, "token": tok, "items": len(plan[1]), "bytes": plan[2]}); return

        if route == "/__wpro_api/session_ack":
            with SESS_LOCK:
                n = 0
                for k, v in SESSIONS.items():
                    if not adm and v.get("user") != user: continue
                    if (body.get("all") or k == str(body.get("sid", ""))) and v.get("new") and not v.get("ack"):
                        v["ack"] = True; n += 1
                if n: _sess_save()
            self.send_json({"ok": True, "acked": n}); return

        if route == "/__wpro_api/session_revoke":
            if body.get("rotate"):
                if not adm: self.send_json({"ok": False, "error": "Admin privileges required"}, 403); return
                n = rotate_secret(); append_audit(user, "SESSION_ROTATE", "signing key rotated, " + str(n) + " session(s) ended", 200, ip)
                self.send_json({"ok": True, "revoked": n, "self": True}, 200, {"Set-Cookie": "wpro_sess=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"}); return
            if body.get("all_others"):
                n = revoke_other_sessions(self.sid, only_user=(None if adm else user))
                append_audit(user, "SESSION_REVOKE", "all other devices (" + str(n) + ")", 200, ip)
                self.send_json({"ok": True, "revoked": n}); return
            sid = str(body.get("sid", ""))
            if revoke_session(sid, only_user=(None if adm else user)):
                append_audit(user, "SESSION_REVOKE", "device " + sid[:6], 200, ip)
                extra = {"Set-Cookie": "wpro_sess=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"} if sid == self.sid else None
                self.send_json({"ok": True, "revoked": 1, "self": sid == self.sid}, 200, extra)
            else: self.send_json({"ok": False, "error": "Session not found"}, 404)
            return

        if route == "/__wpro_api/snapshot":
            if not adm: self.send_json({"ok": False, "error": "Admin privileges required"}, 403); return
            target_mode = body.get("target", "storage")
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_link = os.path.join(ROOT_DIR, "backup")
            backup_dir = os.path.realpath(backup_link) if os.path.exists(backup_link) else "/backup"
            os.makedirs(backup_dir, exist_ok=True)
            cfg_link = os.path.join(ROOT_DIR, "config")
            cfg_dir = os.path.realpath(cfg_link) if os.path.exists(cfg_link) else os.path.realpath(os.path.join(ROOT_DIR, "storage"))
            try:
                if target_mode == "automations" and os.path.exists(cfg_link):
                    zip_name = f"quick_automations_{stamp}.zip"; zip_path = os.path.join(backup_dir, zip_name)
                    cmd = ["zip", "-r", "-y", "-q", zip_path, "automations.yaml", "scripts.yaml", "scenes.yaml", "configuration.yaml", "automations", "packages"]
                    subprocess.run(cmd, cwd=cfg_dir, check=False, timeout=60, **run_as_kwargs())
                elif target_mode == "storage":
                    zip_name = f"backup_storage_{stamp}.zip"; zip_path = os.path.join(backup_dir, zip_name)
                    storage_dir = os.path.realpath(os.path.join(ROOT_DIR, "storage"))
                    cmd = ["zip", "-r", "-y", "-q", zip_path, ".", "-x", "backup/*", "*.db*", "*.log*"]
                    subprocess.run(cmd, cwd=storage_dir, check=False, timeout=120, **run_as_kwargs())
                elif target_mode == "current":
                    cwd_rel = body.get("cwd", "/")
                    current_dir = os.path.realpath(verify_user_path(user, cwd_rel, write=False))
                    if not os.path.isdir(current_dir): raise Exception("Current folder is not valid.")
                    zip_name = f"backup_current_{stamp}.zip"; zip_path = os.path.join(backup_dir, zip_name)
                    cmd = ["zip", "-r", "-y", "-q", zip_path, ".", "-x", "backup/*", "*.db*", "*.log*"]
                    subprocess.run(cmd, cwd=current_dir, check=False, timeout=120, **run_as_kwargs())
                else:
                    zip_name = f"quick_snapshot_{stamp}.zip"; zip_path = os.path.join(backup_dir, zip_name)
                    cmd = ["zip", "-r", "-y", "-q", zip_path, ".", "-x", "backup/*", "*.db*", "*.log*"]
                    subprocess.run(cmd, cwd=cfg_dir, check=False, timeout=120, **run_as_kwargs())

                size_kb = round(os.path.getsize(zip_path) / 1024, 1) if os.path.exists(zip_path) else 0
                append_audit(user, "SNAPSHOT", f"/backup/{zip_name}", 200, ip)
                self.send_json({"ok": True, "filename": zip_name, "path": f"/backup/{zip_name}", "size_kb": size_kb})
            except Exception as e: self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/share":
            action = body.get("action", "create")
            shares = load_shares()
            if action == "revoke":
                tok = body.get("token", "")
                existing = shares.get(tok)
                if existing and not adm and existing.get("owner") != user:
                    self.send_json({"ok": False, "error": "Cannot revoke another user's share"}, 403); return
                shares.pop(tok, None); save_shares(shares)
                append_audit(user, "SHARE_REVOKE", tok, 200, ip)
                self.send_json({"ok": True}); return

            rel_path = body.get("path", "")
            try: ttl = max(60, min(int(body.get("ttl", 3600)), 365 * 86400))
            except (TypeError, ValueError): ttl = 3600
            try: max_uses = max(0, min(int(body.get("max_uses", 0) or 0), 1000000))
            except (TypeError, ValueError): max_uses = 0
            password = str(body.get("password", "") or "")
            if len(password) > 128: self.send_json({"ok": False, "error": "Password is too long (max 128 characters)"}, 400); return
            try:
                full = verify_user_path(user, rel_path, write=False)
                if full == ROOT_DIR or not os.path.exists(full): self.send_json({"ok": False, "error": "Target path does not exist"}, 400); return
                is_dir = os.path.isdir(full)
                base_name = os.path.basename(full.rstrip("/")) or "root"
                display_name = (base_name + ".zip") if is_dir else base_name
                token = secrets.token_urlsafe(10)
                now = int(time.time())
                entry = {"path": rel_path, "name": display_name, "is_dir": is_dir, "owner": user,
                         "created": now, "exp": now + ttl, "max_uses": max_uses, "uses": 0}
                if password: entry["pw_salt"], entry["pw_hash"] = hash_share_pw(password)
                with SHARE_LOCK:
                    shares = load_shares(); shares[token] = entry; save_shares(shares)
                append_audit(user, "SHARE_CREATE", rel_path, 200, ip)
                self.send_json({"ok": True, "token": token, "exp": now + ttl, "name": display_name,
                                "is_dir": is_dir, "max_uses": max_uses, "has_password": bool(password)})
            except PermissionError as e: self.send_json({"ok": False, "error": str(e)}, 403)
            except Exception as e: self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/audit_clear":
            if not adm: self.send_json({"ok": False, "error": "Admin privileges required"}, 403); return
            try:
                open(AUDIT_FILE, "w").close()
                append_audit(user, "AUDIT_CLEAR", "/", 200, ip)
                self.send_json({"ok": True})
            except Exception as e: self.send_json({"ok": False, "error": str(e)}, 500)
            return

        if route == "/__wpro_api/perm_set":
            if not adm: self.send_json({"ok": False, "error": "Admin privileges required"}, 403); return
            p_rel = body.get("path", "")
            try:
                res = perm_apply(user, p_rel, body.get("mode"), body.get("recursive"), body.get("scope", "all"),
                                 str(body.get("owner", "") or "").strip(), str(body.get("group", "") or "").strip())
                append_audit(user, "CHMOD " + res["mode"] + (" -R" if body.get("recursive") else ""), p_rel, 200, ip)
                self.send_json(res)
            except (ValueError, PermissionError, OSError) as e: self.send_json({"ok": False, "error": str(e)}, 400)
            return

        if route == "/__wpro_api/exec":
            if not adm: self.send_json({"output": "Admin privileges required.\n", "code": 403}, 403); return
            if not TERMINAL_ENABLED: self.send_json({"output": "Web Terminal is disabled (ENABLE_TERMINAL=false).\n", "code": 403}, 403); return
            cmd_str = body.get("cmd", "").strip()
            cwd_rel = body.get("cwd", "/")
            if not cmd_str: self.send_json({"output": ""}); return
            try:
                cwd_full = os.path.realpath(verify_user_path(user, cwd_rel, write=False))
                if not os.path.isdir(cwd_full): cwd_full = ROOT_DIR
                proc = subprocess.run(cmd_str, shell=True, cwd=cwd_full, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      timeout=25, text=True, env=child_env(), **run_as_kwargs())
                append_audit(user, "TERM_CMD", cmd_str[:80], proc.returncode, ip)
                self.send_json({"output": proc.stdout, "code": proc.returncode})
            except subprocess.TimeoutExpired: self.send_json({"output": "Command timed out after 25s.\n", "code": 124})
            except Exception as e: self.send_json({"output": f"Error: {e}\n", "code": 1})
            return

        self.send_json({"error": "Unknown endpoint"}, 404)

if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), WProHandler)
    server.serve_forever()
PYEOF
chmod 700 /usr/local/bin/wpro_api.py

# 10. Khởi chạy Python API ở chế độ nền
supervise "OmniDrive API" 0 python3 /usr/local/bin/wpro_api.py "${API_PORT}"
API_PID=$SUPERVISE_PID
log_info "Started OmniDrive Pro API & RBAC Auth Engine on 127.0.0.1:${API_PORT}"

# 10b. Real client IP behind reverse proxy / Cloudflare Tunnel
REAL_IP_CONF=""
# Mặc định chỉ tin 127.0.0.1. Dải cũ 172.16.0.0/12 tin cả gateway Docker (docker-proxy) -> client LAN có thể
# giả mạo X-Forwarded-For để né giới hạn đăng nhập. Chạy sau Cloudflared/NPM/Traefik thì khai báo IP/dải của proxy.
TRUSTED_PROXIES="${TRUSTED_PROXIES:-127.0.0.1}"
REAL_IP_HEADER="${REAL_IP_HEADER:-X-Forwarded-For}"
if [ -n "$TRUSTED_PROXIES" ] && [ "${TRUSTED_PROXIES,,}" != "none" ] && [[ "$REAL_IP_HEADER" =~ ^[A-Za-z0-9-]+$ ]]; then
    printf 'pid /tmp/ri_test.pid;\nerror_log /dev/stderr;\nevents {}\nhttp { access_log off; set_real_ip_from 127.0.0.1; real_ip_header X-Forwarded-For; real_ip_recursive on; }\n' > /tmp/ri_test.conf
    if nginx -t -c /tmp/ri_test.conf >/dev/null 2>&1; then
        IFS=',' read -ra _TP <<< "$TRUSTED_PROXIES"
        for _cidr in "${_TP[@]}"; do
            _cidr="${_cidr// /}"
            if [[ "$_cidr" =~ ^[0-9a-fA-F:./]+$ ]]; then
                REAL_IP_CONF+="        set_real_ip_from ${_cidr};"$'\n'
            elif [ -n "$_cidr" ]; then
                log_warn "Ignoring invalid TRUSTED_PROXIES entry: ${_cidr}"
            fi
        done
        if [ -n "$REAL_IP_CONF" ]; then
            REAL_IP_CONF+="        real_ip_header ${REAL_IP_HEADER};"$'\n'"        real_ip_recursive on;"$'\n'
            log_info "Real client IP enabled (trusted proxies: ${TRUSTED_PROXIES}, header: ${REAL_IP_HEADER})."
        fi
    else
        log_warn "nginx realip module not available; client IP detection disabled."
    fi
    rm -f /tmp/ri_test.conf
fi

# 11. Sinh file cấu hình Nginx chính (chuyển tiếp X-Original-* để kiểm tra RBAC/read_only)
cat <<EOF > "$NGINX_CONF"
load_module /usr/lib/nginx/modules/ngx_http_dav_ext_module.so;
load_module /usr/lib/nginx/modules/ngx_http_fancyindex_module.so;

user ${RUN_USER} ${RUN_GROUP};
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
    # File người dùng tải lên có thể chứa script (HTML/SVG/XML/JS): bắt buộc tải về thay vì hiển thị trên cùng origin với giao diện
    map \$uri \$wpro_force_dl { default ""; "~*\.(html?|xht|xhtml|shtml|svgz?|xml|xsl|xslt|js|mjs)\$" "attachment"; }

    map \$request_method \$is_mutating_or_dl { default 0; PUT 1; DELETE 1; MKCOL 1; COPY 1; MOVE 1; GET 1; }

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
    limit_req_zone \$binary_remote_addr zone=share_limit:10m rate=5r/s;

    server {
        ${LISTEN_DIRECTIVE}
        ${SSL_DIRECTIVES}
        server_name _;
${REAL_IP_CONF}
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        location ^~ /.fancyindex/vendor/ { alias /usr/share/nginx/fancyindex/vendor/; access_log off; gzip on; gzip_types application/javascript text/css; gzip_min_length 1024; add_header Cache-Control "public, max-age=604800" always; }
        location ^~ /.fancyindex/ { alias /usr/share/nginx/fancyindex/; access_log off; }
        location = /__wpro_api/login { client_max_body_size 16k; limit_req zone=dav_auth_limit burst=15 nodelay; proxy_pass http://127.0.0.1:${API_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; access_log off; }
        location = /__wpro_api/logout { client_max_body_size 16k; proxy_pass http://127.0.0.1:${API_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; access_log off; }
        location = /__wpro_auth_check {
            internal;
            proxy_pass http://127.0.0.1:${API_PORT}/__wpro_api/auth_check;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Original-URI \$request_uri;
            proxy_set_header X-Original-Method \$request_method;
            proxy_set_header X-Original-Destination \$http_destination;
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
        location ^~ /s/ { client_max_body_size 16k; limit_req zone=share_limit burst=15 nodelay; limit_req_status 429; proxy_pass http://127.0.0.1:${API_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; }
        location ^~ /__wpro_api/ { client_max_body_size 1m; auth_request /__wpro_auth_check; error_page 401 = @login_or_basic; proxy_pass http://127.0.0.1:${API_PORT}; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_read_timeout 600s; access_log off; }
        ${DOTFILES_RULE}

        location / {
            limit_req zone=dav_auth_limit burst=40 nodelay;
            auth_request /__wpro_auth_check;
            error_page 401 = @login_or_basic;

            root ${ROOT_DIR};
            index __omnidrive_no_index__;
            add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Content-Disposition \$wpro_force_dl always;
            ${INDEX_CONFIG}

${ROOT_LOCK_RULES}
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
chmod 600 "$NGINX_CONF"

# 12. Kiểm tra cú pháp Nginx & chạy với Graceful Shutdown
log_info "Checking Nginx configuration syntax..."
if ! nginx -t 2>&1; then
    log_error "Invalid Nginx configuration, see the details above."
    exit_nok "Stopping container due to an Nginx configuration error."
fi
log_info "Nginx configuration is valid."

log_info "OmniDrive Pro v${APP_VERSION} is ready on port ${WEBDAV_PORT}!"
nginx -g "daemon off;" &
NGINX_PID=$!
wait "${NGINX_PID}"
