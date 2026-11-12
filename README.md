# OmniDrive Pro — Multi-Protocol Storage Hub & Cloud IDE (Docker Edition)

<p align="center">
  <img src="icon.png" alt="OmniDrive Pro Logo" width="96" height="96" style="border-radius: 22px;" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.29-blue.svg" alt="Version" />
  <img src="https://img.shields.io/badge/nginx-1.30.6--r0-009639.svg" alt="Nginx" />
  <img src="https://img.shields.io/badge/alpine%20base-3.24-0D597F.svg" alt="Alpine Base" />
  <img src="https://img.shields.io/badge/protocols-WebDAV%20%7C%20SMB%20%7C%20SFTP%20%7C%20FTP-8b5cf6.svg" alt="Protocols" />
  <img src="https://img.shields.io/badge/platform-Docker%20%7C%20CasaOS%20%7C%20Portainer-0db7ed.svg" alt="Platform" />
  <img src="https://img.shields.io/badge/arch-linux%2Famd64%20%7C%20linux%2Farm64-blue.svg" alt="Arch" />
  <img src="https://img.shields.io/badge/maintained-yes-brightgreen.svg" alt="Maintained" />
</p>

**OmniDrive Pro (Docker Edition)** is an all-in-one, lightweight Multi-Protocol Storage Gateway (**WebDAV, SMB/Samba, SFTP, FTP**), iOS Glassmorphism File Manager, Cloud Code IDE, and System Operations Suite built for Linux Docker hosts, **CasaOS**, **Portainer**, Ubuntu Server, and Raspberry Pi.

---

## 🌟 About

**OmniDrive Pro** transforms any Linux server or NAS into a high-speed, security-hardened multi-protocol storage server and full-featured Cloud IDE inside a single lightweight Alpine container. 

Mount your entire Linux host filesystem or custom volumes as a native network drive inside **iOS/iPadOS Files**, **macOS Finder**, **Windows Explorer**, **Infuse / VLC**, or **SFTP/FTP clients** (over LAN, Tailscale, or Cloudflare Zero Trust Tunnels), or manage files, run terminal commands, and edit code directly from any modern browser.

This repository automatically tracks official **Alpine Linux** and **Nginx** upstream releases via GitHub Actions and publishes multi-architecture Docker images (`linux/amd64` and `linux/arm64`) to GitHub Container Registry (`ghcr.io`).

---

## ✨ Key Features

- **4-in-1 Multi-Protocol Storage Gateway:**
  - **WebDAV & Web UI (Port `8090`):** Full WebDAV Class 1 & 2 (`dav-ext` + `davlock`) for Cloudflare Tunnel, macOS Finder, Windows Explorer, and Rclone.
  - **SMB / Samba v3 (Port `445`):** Native network drive mounting for **iOS/iPadOS Files**, **macOS Finder (`smb://`)**, **Windows Explorer (`\\ip\`)**, and 4K media streaming to **Infuse / VLC**.
  - **SFTP Server (Port `2222`):** Encrypted SSH File Transfer Protocol for **Termius, Cyberduck, Transmit, FileZilla, WinSCP, and FE File Explorer**.
  - **FTP Server (Port `2121`, Passive `21000–21002`):** High-speed LAN file transfers for network scanners, cameras, and standard FTP clients.
- **Hybrid Dual-Auth & iOS Glass Login UI:** Replaces ugly browser Basic Auth popups with a sleek **iOS Glassmorphism Login Page (`login.html`)** featuring `HMAC-SHA256` 30-day session cookies, while seamlessly supporting HTTP Basic Auth in the background for native WebDAV clients.
- **Full Host Filesystem & Auto-Mount Discovery:**
  - **Optional (opt-in):** mount `/` to `/host_root:rw` to inspect and edit **100% of your Linux server files** under `/host_system`.
  - **Zero-Config `/mnt/*` Auto-Discovery:** Any host folder mounted under `/mnt/<folder_name>` is automatically discovered and exposed across the Web UI, WebDAV, SMB, SFTP, and FTP without manual config edits.
- **Professional Ace Cloud Code IDE:**
  - Syntax highlighting (One Dark theme) for YAML, Python, JSON, Shell, JS/TS, HTML/CSS, PHP, SQL, Markdown, and Dockerfile.
  - **Code Mini Map & Multi-Cursor (`✚ Cursor`):** Live right-hand code minimap for fast scrolling through long configuration files, plus multi-cursor editing (`Alt/Option + Click`).
  - **Real-Time YAML Linter (`js-yaml`):** Live syntax validation supporting custom YAML tags (`!include`, `!secret`, `!env_var`) with gutter annotations.
  - **Anti-Blank Guard & Unsaved Changes Protection:** Tracks unsaved edits (`● UNSAVED`) and prompts with custom iOS Glass confirmation dialogs before saving, closing with unsaved changes, or deleting files.
  - **Git Status Integration:** Displays the active branch badge (`⎇ main`) and marks modified (`🟡`) or newly added/untracked (`🟢`) files directly in the file list.
- **Advanced Document, Media & Binary Viewers:**
  - **Direct `PDF.js` Canvas Viewer:** Multi-page PDF rendering with page navigation and zoom controls (`−` / `＋`) without downloading.
  - **Pro Media Player & Background Audio:** Video/audio playback with `↺ -10s` / `↻ +10s` seek, speed control (`0.5x` ➔ `2.0x`), and an **Apple Music-style Mini Player** for background audio playback while browsing or coding.
  - **Hex / Binary & Archive Inspector:** Inspects binary/database files (`.db`, `.sqlite`, `.bin`) in side-by-side `HEX + ASCII` view, and previews `.zip` and `.tar` archives without extraction.
- **System Operations, Sharing & Security Suite:**
  - **Integrated Web Terminal (`xterm.js`):** Execute shell and Git commands (`df -h`, `ls -la`, `git status`, `git pull`) directly from the Web UI.
  - **Storage Analytics (Donut Chart):** Visualizes total host disk capacity, used/free space, and per-folder storage breakdown.
  - **1-Tap Quick Zip Snapshot:** Instant 1-tap `.zip` snapshot straight into `/backup` before editing critical configuration files.
  - **Temporary Expiry Share Links (`/s/<token>`):** Generate public download links for any **file or folder** (folders are automatically zipped on the fly) with custom expiration (`1 Hour`, `6 Hours`, `24 Hours`, `7 Days`) without exposing your password.
  - **Signed-in Devices:** see every browser/device that is logged in (device, IP, last activity), sign out any single device or all other devices — the login token is revoked instantly on the server.
  - **Safer Share Links:** custom expiry (hours to 365 days), limit the **number of downloads** (the link dies when the limit is reached) and protect a link with its **own password** (stored as a salted PBKDF2 hash).
  - **Security Audit Log:** Tracks logins, file modifications (`PUT`), deletions (`DELETE`), snapshots, and share-link downloads in real time.

---

## 🚀 Quick Start (Docker Compose)

> ⚠️ **Read before you start** — things to change or know about the defaults:
> 1. **Change `OMNI_PASS`.** The default password is public. Anyone who guesses it gets a root-level terminal and full file access (see [Security Notes](#-security-notes)).
> 2. **Set `FTP_PASV_ADDRESS`** to your server's LAN IP *only if you use FTP* (find it with `hostname -I`). Not needed for Web UI, WebDAV, SMB or SFTP.
> 3. **Terminal and full-host access are OFF by default** (`ENABLE_TERMINAL=false`, `/:/host_root` commented out). Enable them only if you understand the risk — see [Security Notes](#-security-notes).
> 4. **Check that the ports are free** (`8090`, `445`, `2222`, `2121`, `21000-21002`). See [Troubleshooting](#-troubleshooting) if Docker reports `port is already allocated`.

Create a `docker-compose.yml` file in an **empty folder** on your Linux server:

```yaml
name: omnidrive-pro

services:
  omnidrive-pro:
    image: ghcr.io/boystyle2010/omnidrive-pro:latest
    container_name: omnidrive-pro
    restart: unless-stopped
    labels:
      icon: "https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png"
      name: "OmniDrive Pro"
      web: "8090"
    environment:
      - TZ=America/Denver

      # !!! CHANGE THIS PASSWORD before first start !!!
      - OMNI_USER=admin
      - OMNI_PASS=changeme_strong_password

      - SMB_ENABLED=true
      - SFTP_ENABLED=true
      - FTP_ENABLED=true
      - FANCY_UI=true
      - SHOW_DOTFILES=true

      # Web Terminal runs shell commands as root inside the container.
      # Disabled by default. Set to true only if you trust everyone who can log in
      # and the service is not reachable from untrusted networks.
      - ENABLE_TERMINAL=false

      # Root access.
      #   false (default): everything runs as the normal user "omnidrive" (PUID:PGID) and can only touch
      #          what that user may touch. Make sure PUID/PGID own the folders you want to manage
      #          (the 4 data volumes are fixed automatically, a mounted host folder is NOT touched).
      #   true : file operations, Web Terminal and zip jobs run as root -> full file-manager power.
      #          Needed to manage system / other users' files (e.g. a mounted /DATA or the whole host).
      - ROOT_ACCESS=false
      # - PUID=1000
      # - PGID=1000

      # FTP encryption (FTPS, explicit TLS, certificate is generated automatically):
      #   optional (default) = encrypted if the client asks for it, plain FTP still works
      #   required           = plain FTP is refused
      #   off                = no encryption
      # - FTP_TLS=optional

      # Root lock (default true): nothing can be created, renamed or deleted directly at the top level
      # (Root) over WebDAV / Web UI / SFTP / FTP; the "OmniDrive" SMB share is read-only (use the named SMB shares to write).
      # - LOCK_ROOT=true

      # FTP Passive Mode only: uncomment and set this to the LAN IP of the
      # machine running Docker (find it with: hostname -I).
      # Without it, FTP clients may hang when listing folders.
      # Not needed for Web UI, WebDAV, SMB or SFTP.
      # - FTP_PASV_ADDRESS=192.168.1.100

      # Reverse proxy / Cloudflare Tunnel / Nginx Proxy Manager users:
      # list the IP or subnet your proxy connects from (comma-separated) so the real
      # client IP is used for the audit log, rate limiting and login lockout.
      # Default: 127.0.0.0/8,172.16.0.0/12 (loopback + Docker networks). Use "none" to disable.
      # - TRUSTED_PROXIES=192.168.1.10,172.16.0.0/12
      # - REAL_IP_HEADER=X-Forwarded-For

      # Largest folder (in MB) that can be downloaded as a zip via a share link.
      # - SHARE_ZIP_MAX_MB=2048
    ports:
      - "8090:8090"               # Web UI, WebDAV & Share Links
      - "445:445"                 # SMB / Samba
      - "2222:2222"               # SFTP
      - "2121:2121"               # FTP control port
      - "21000-21002:21000-21002" # FTP passive data ports
    volumes:
      # 1. OmniDrive Pro config, audit log & share links
      - ./data:/data
      - ./ssl:/ssl
      - ./backup:/backup
      - ./storage:/storage
      - ./media:/media
      - ./share:/share

      # 2. OPTIONAL - FULL HOST ACCESS. Uncomment to browse/edit EVERY file on the
      #    host (appears as /host_system). Powerful and dangerous: anyone who can
      #    log in can read, change or delete anything on your server.
      # - /:/host_root:rw

      # 3. OPTIONAL - shortcuts: any folder mounted under /mnt/<Name> appears on the
      #    home screen and over every protocol. Adjust to folders that exist on your
      #    system, or remove. (/DATA exists on CasaOS / ZimaOS only.)
      # - /DATA:/mnt/DATA
      # - /home:/mnt/home
    x-casaos:
      title:
        en_us: OmniDrive Pro
      icon: https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png

x-casaos:
  title:
    en_us: OmniDrive Pro
  tagline:
    en_us: Multi-protocol storage hub
  icon: https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png
  main: omnidrive-pro
  index: /
  port_map: "8090"
```

Start the container (run this **inside the folder that contains `docker-compose.yml`**):

```bash
docker compose up -d
```

Open your browser and navigate to:
👉 **`http://<YOUR_SERVER_IP>:8090`**

### Changing the web port

Only change the number on the **left** of the colon (the port on your server). Keep the right side at `8090`, because that is the port nginx listens on inside the container:

```yaml
ports:
  - "8099:8090"   # open http://<YOUR_SERVER_IP>:8099
```

If you use a reverse proxy or tunnel (Nginx Proxy Manager, Cloudflare Tunnel, Caddy…), point it at the new port. The `ports:` mapping lives in **your local** `docker-compose.yml`, not in the image, so pulling a new image never changes it.

### Updating

```bash
docker compose pull
docker compose up -d
```

Your settings, users, audit log and share links are stored in `./data` and are preserved across updates. After updating, hard-refresh the browser (`Ctrl+F5` / `Cmd+Shift+R`) so it does not use cached UI files.

---

## 🏠 How to Install on CasaOS (1-Click Import)

You can install **OmniDrive Pro** directly onto your **CasaOS** dashboard with its custom icon and full host file management in under 1 minute:

### Step 1: Check Port 445 (If CasaOS Samba is running)
CasaOS uses port `445` for its built-in file sharing by default.
* **Option A (Recommended if you want OmniDrive Pro to handle SMB on port 445):** Stop Samba on the host (`sudo systemctl stop smbd nmbd && sudo systemctl disable smbd nmbd`), or
* **Option B (Keep CasaOS Samba):** Change the SMB port mapping in the Compose config below from `"445:445"` to `"4450:445"`.

### Step 2: Import into CasaOS
1. On your **CasaOS Dashboard**, click the **`+` (Add)** button in the top-right corner of the **Apps** section and select **Install a customized app** (or open the **App Store** ➔ click **Custom Install** in the top right).
2. In the **Install a customized app** window, click the **Import** button (top-right icon next to the close button).
3. Select the **Docker Compose** tab, paste the following CasaOS-ready configuration, and click **Submit**:

```yaml
name: omnidrive-pro
services:
  omnidrive-pro:
    image: ghcr.io/boystyle2010/omnidrive-pro:latest
    container_name: omnidrive-pro
    restart: unless-stopped
    environment:
      - TZ=America/Denver
      - OMNI_USER=admin
      - OMNI_PASS=changeme_strong_password
      - SMB_ENABLED=true
      - SFTP_ENABLED=true
      - FTP_ENABLED=true
      - FANCY_UI=true
      - SHOW_DOTFILES=true
      # Web Terminal runs root commands. Set to true only if you trust every user.
      - ENABLE_TERMINAL=false
      # true = act as root (full power). false (default) = act as the normal user "omnidrive" (PUID:PGID).
      - ROOT_ACCESS=false
      # FTP only: set to your server's LAN IP (hostname -I), otherwise leave empty
      - FTP_PASV_ADDRESS=
    labels:
      icon: https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png
      name: OmniDrive Pro
      web: "8090"
    ports:
      - target: 8090
        published: "8090"
        protocol: tcp
      - target: 445
        published: "445"
        protocol: tcp
      - target: 2222
        published: "2222"
        protocol: tcp
      - target: 2121
        published: "2121"
        protocol: tcp
      - target: 21000
        published: "21000"
        protocol: tcp
      - target: 21001
        published: "21001"
        protocol: tcp
      - target: 21002
        published: "21002"
        protocol: tcp
    volumes:
      - type: bind
        source: /DATA/AppData/omnidrive-pro/data
        target: /data
      - type: bind
        source: /DATA/AppData/omnidrive-pro/backup
        target: /backup
      - type: bind
        source: /DATA/AppData/omnidrive-pro/storage
        target: /storage
      # OPTIONAL full host access (dangerous - anyone who logs in can change any file).
      # Remove the leading "#" on the next three lines to enable it.
      # - type: bind
      #   source: /
      #   target: /host_root
      # OPTIONAL shortcuts (adjust to folders that exist on your system):
      - type: bind
        source: /DATA
        target: /mnt/DATA
      - type: bind
        source: /home
        target: /mnt/home
    x-casaos:
      author: Minh Hua
      category: Cloud
      hostname: ""
      icon: https://raw.githubusercontent.com/boystyle2010/omnidrive-pro-docker/main/icon.png
      index: /
      port_map: "8090"
      scheme: http
      title:
        en_us: OmniDrive Pro
```

4. Verify your **Environment Variables** in the CasaOS UI form, then click **Install**:
   * **`OMNI_PASS`** — change it from the default.
   * **`FTP_PASV_ADDRESS`** — set to your server's LAN IP only if you use FTP, otherwise leave empty.
   * **Port `8090` already used?** Change the *published* port (and `port_map` under `x-casaos`) to a free one, e.g. `8099`.
5. Once installed, click the **OmniDrive Pro** icon on your CasaOS dashboard to launch the Web UI!

---

## ⚙️ Environment Variables & Advanced Configuration

On first boot, OmniDrive Pro automatically generates `/data/options.json` from your environment variables:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `OMNI_USER` | `admin` | Default administrator username for Web UI, WebDAV, SMB, SFTP, and FTP. |
| `OMNI_PASS` | `changeme_strong_password` | Default administrator password. |
| `WEBDAV_PORT` | `8090` | Internal HTTP/HTTPS port for the Web UI and WebDAV server. |
| `SMB_ENABLED` | `true` | Enable or disable the built-in Samba server (`445/tcp`). |
| `SFTP_ENABLED` | `true` | Enable or disable the built-in OpenSSH SFTP server (`2222/tcp`). |
| `FTP_ENABLED` | `true` | Enable or disable the built-in `vsftpd` server (`2121/tcp`). |
| `FTP_PASV_ADDRESS`| *(empty)* | Host LAN IP address for FTP Passive data connections (`21000-21002`). **Required for FTP only.** Use the IP your FTP client connects to (LAN IP, or Tailscale IP when connecting over Tailscale). Give the server a static IP / DHCP reservation so it does not change. |
| `MAX_UPLOAD_SIZE` | `0` | Max upload size (`0` = unlimited). |
| `SHOW_DOTFILES` | `true` | Show hidden files and folders starting with `.` (e.g., `.env`, `.gitignore`). |
| `ROOT_ACCESS` | `false` | `false`: Web UI file operations, WebDAV, SMB, FTP, the Terminal and zip/share jobs act as the normal user **`omnidrive`** (`PUID:PGID`) and can only touch what that user may touch. `true`: they act as **root** (full file-manager power, can manage any file, e.g. a mounted `/DATA` or the whole host). `RUN_AS_ROOT` is still accepted as the old name. |
| `LOCK_ROOT` | `true` | Nothing can be created, renamed or deleted directly at Root (`/`) over WebDAV, Web UI, SFTP and FTP — only inside a share or folder. The unified **OmniDrive** SMB share becomes read-only (Samba cannot lock only the top level); write through the named SMB shares (`storage`, `media`, `share`, `backup`, `/mnt/<Name>`). Set `false` to disable. |
| `FTP_TLS` | `optional` | FTPS (explicit TLS 1.2+). A self-signed certificate is generated once in `./data/wpro/` (or your `/ssl` certificate is reused). `optional`: encrypted when the client asks, plain FTP still works. `required`: plain FTP is refused. `off`: no encryption. Clients show a certificate warning for the self-signed certificate — accept it or use your own certificate. |
| `OMNI_PASS_FILE` | *(empty)* | Optional path of a file (Docker secret) that holds the password instead of `OMNI_PASS`. |
| `PUID` / `PGID` | `1000` / `1000` | User and group IDs used when `ROOT_ACCESS=false`. Use the owner of the folders you want to manage (`id <user>` on the host). The 4 data volumes (`storage`, `media`, `share`, `backup`) are handed to this user automatically; mounted host folders are never re-owned. |
| `ENABLE_TERMINAL` | `true` (image) / `false` (compose files in this repo) | Enables the Web Terminal, which runs shell commands as **root**. When `false`, the Terminal button is hidden and the API refuses commands. |
| `TRUSTED_PROXIES` | `127.0.0.0/8,172.16.0.0/12` | Comma-separated IPs/subnets of your reverse proxy / tunnel. Only these may tell OmniDrive the real client IP (via `REAL_IP_HEADER`). Needed for correct audit-log IPs, per-user rate limiting and login lockout behind a proxy. Use `none` to disable. |
| `REAL_IP_HEADER` | `X-Forwarded-For` | Header carrying the real client IP (e.g. `CF-Connecting-IP` for Cloudflare). |
| `SHARE_ZIP_MAX_MB` | `2048` | Maximum size (MB) of a folder that can be downloaded as a zip through a share link. Larger folders are refused (protects host disk and CPU). |
| `SSL` | `false` | Set to `true` to enable native HTTPS using `/ssl/fullchain.pem` and `/ssl/privkey.pem`. |

> **Multi-User & Custom Share Configuration:** After the first run, you can edit `/data/options.json` directly (even from inside OmniDrive Pro's own Code Editor!) to add multiple user accounts or custom read-only share rules, then restart the container.

---

> **Environment variables are re-applied on every start.** Changing `OMNI_USER` / `OMNI_PASS` in `docker-compose.yml` and recreating the container (`docker compose up -d`) overwrites the first user in `/data/options.json`.

---

## 🔒 Security Notes

OmniDrive Pro is powerful by design, so please harden it before exposing it beyond your home network:

- **Change the default password** (`changeme_strong_password`). Use a long, unique one.
- **The Web Terminal runs shell commands as root inside the container** and is **disabled by default** (`ENABLE_TERMINAL=false`). Combined with the optional `/:/host_root:rw` mount, anyone who logs in can read, modify or delete **any file on your host**. Enable them only on a trusted network, behind strong authentication.
- **CSRF protection:** every state-changing API call requires a custom header that browsers will not send cross-origin, so other websites (or other apps on sibling subdomains) cannot trigger actions with your logged-in session.
- **Do not publish ports directly to the internet.** Prefer a VPN (Tailscale / WireGuard) or a Cloudflare Zero Trust Tunnel with extra access control. If you must expose it, enable HTTPS (`SSL=true`) or terminate TLS at a reverse proxy.
- **Share links (`/s/<token>`) are public** to anyone who has the URL until they expire, run out of downloads or are revoked. Set a **max download count** and a **password** for anything sensitive, use the shortest expiry that works, and revoke links you no longer need. Every successful download counts as one use (a resumed or repeated download counts again); wrong passwords never count and are rate-limited.
- **Signed-in devices:** open **Security** to see every logged-in browser (device, IP, a **NEW DEVICE** label for a device that never signed in before) and sign out any of them, or use **Sign out all & rotate key**, which also replaces the session signing key so no old cookie can ever work again. Revocation is immediate. Logins made with Basic Auth by WebDAV/file apps are stateless and are not listed — change the password to cut those off. After upgrading from an older version everyone has to sign in once more.
- **Privilege mode:** `ROOT_ACCESS=false` (default) limits the Web UI, WebDAV, SMB, FTP and Terminal to the normal user `omnidrive` (`PUID:PGID`). `ROOT_ACCESS=true` gives full access to every file the container can see — use it for a "professional" file manager, only behind strong authentication. In root mode SFTP/FTP accounts remain normal system users (not root).
- **Root lock (`LOCK_ROOT=true`, default):** the virtual top level cannot receive stray files or folders over WebDAV, the Web UI, SFTP or FTP. The unified `OmniDrive` SMB share is read-only for the same reason; use the named SMB shares to write.
- **FTP encryption:** FTPS (explicit TLS) is enabled with an auto-generated certificate (`FTP_TLS=optional`). Set `FTP_TLS=required` to refuse plain FTP, and use a client that supports "FTP over explicit TLS".
- **Only expose the protocols you use.** Set `SMB_ENABLED`, `SFTP_ENABLED` or `FTP_ENABLED` to `false` and remove their `ports:` lines when not needed. Prefer SFTP or SMB; for FTP use `FTP_TLS=required`.
- **Back up before editing** critical files (use the **Quick Zip** button).
- **Login is rate-limited:** after 10 failed attempts from the same IP + username, login is blocked for 5 minutes. This also applies to WebDAV Basic Auth. Behind a reverse proxy or tunnel, set `TRUSTED_PROXIES` so the *real* client IP is used. The session cookie is marked `Secure` automatically when you browse over HTTPS (native SSL, reverse proxy or Cloudflare Tunnel).
- **Passwords are hashed.** At every start `/data/options.json` is rewritten without plain-text passwords: only a salted PBKDF2-SHA256 hash (web / WebDAV login) and a salted SHA-512 crypt hash (SFTP / FTP) are kept, file mode `600`. SMB cannot work from a salted hash, so Samba keeps its own NT-hash database in `./data/wpro/samba` (mode `700`; an NT hash is an unsalted MD4 and equivalent to a password for SMB, so treat `./data` as secret). **Note:** `OMNI_PASS` in your `docker-compose.yml` is still plain text — use `OMNI_PASS_FILE` (Docker secret) if that matters. After the first successful start you can **delete `OMNI_PASS` from your compose file**: the hashed account keeps working (SMB uses its own stored hash). To change a password: change `OMNI_PASS`, or type a new plain-text `"password"` for that user in `options.json` and restart — it is hashed again immediately. Keep `./data` private and never commit it to git.
- **No third-party scripts at runtime:** all front-end libraries are downloaded when the image is built and served from the container itself.
- **Do not store files at the Root screen.** Root is a virtual view that is rebuilt on every start (only its shortcut links are recreated; stray files are not part of any volume and are lost when the container is recreated). Open a folder (`storage`, `media`, `share`, `host_system`…) first — the Web UI blocks uploads and new files at Root to protect you from data loss.

---

## 🛠 Troubleshooting

| Problem | Cause & fix |
| :--- | :--- |
| `no configuration file provided: not found` | You are not in the folder that contains `docker-compose.yml`. `cd` into it first, or pass the file with `docker compose -f /path/to/docker-compose.yml up -d`. |
| `Bind for 0.0.0.0:8090 failed: port is already allocated` | Another container or service already uses that port. Find it with `sudo ss -tlnp \| grep 8090` and `docker ps`, then either stop it or change the **left** side of the mapping, e.g. `"8099:8090"`. Same applies to `445`, `2222` and `2121`. |
| Port `445` already in use (CasaOS / ZimaOS / host Samba) | The host's own Samba owns port 445. Either stop it (`sudo systemctl disable --now smbd nmbd`) or map SMB to another port, e.g. `"4450:445"`, and connect with `smb://<SERVER_IP>:4450/OmniDrive`. |
| `No services to build` | Your compose file has no `build:` section. That is normal: the image is pulled, not built. Use `docker compose pull && docker compose up -d`. |
| I changed the compose file on GitHub but nothing changed on my server | `docker-compose.yml` is a **local file**. Pulling a new image does not update it. Edit the file on your server (or re-download it) and run `docker compose up -d`. |
| FTP connects but folder listing hangs or times out | `FTP_PASV_ADDRESS` is missing or wrong. Set it to the IP your client connects to and recreate the container. Also make sure ports `21000-21002` are open in your firewall. |
| Rename / Duplicate / Move does nothing | Update to the latest image (`docker compose pull && docker compose up -d`) and hard-refresh the browser. If a toast like `Rename failed (502)` appears, check `docker logs omnidrive-pro` and your reverse proxy: it must forward the original `Host` header. |
| Terminal button is missing | The Web Terminal is disabled by default. Set `ENABLE_TERMINAL=true` in `docker-compose.yml` and recreate the container (`docker compose up -d`). |
| Audit log / lockout shows my proxy's IP, or I get `503` when many files load | Behind a reverse proxy or tunnel, add its IP/subnet to `TRUSTED_PROXIES` (check `docker logs omnidrive-pro` for the address it sees). Otherwise every visitor shares one IP and one rate limit. |
| `403 Missing CSRF header` from a script or custom client | State-changing calls to `/__wpro_api/*` must send `X-WPro-CSRF: 1`. The built-in UI does this automatically; add the header to your own scripts. |
| Everyone was logged out after updating | Expected once: sessions are now stored on the server so they can be revoked. Sign in again. |
| `Permission denied` with `ROOT_ACCESS=false` (the default) | The unprivileged user cannot access that folder. Set `PUID`/`PGID` to the owner of the folder (`id <user>`), or fix its ownership/permissions on the host. |
| Share link says *expired or invalid* but was just created | It reached its **max downloads** or its expiry time, or it was revoked. Create a new link. |
| Web UI looks outdated after an update | Browser cache. Hard-refresh with `Ctrl+F5` / `Cmd+Shift+R`. |
| Container name / icon not shown on CasaOS or ZimaOS dashboard | The dashboard reads metadata only when a container is **created**. Make sure `x-casaos` (or the `name` / `icon` labels) is present, then recreate it: `docker rm -f omnidrive-pro && docker compose up -d`. Or install via **Custom Install → Import**. |
| Cannot log in, or forgot the password | Set `OMNI_USER` / `OMNI_PASS` in `docker-compose.yml` and recreate the container, or edit `./data/options.json` and restart. |
| Useful debugging commands | `docker logs --tail 50 omnidrive-pro` · `docker compose config` (validates your YAML) · `docker ps -a` |

---

## 🔌 Client Connection Guide

Tap the **Connect** button in the OmniDrive Pro Web UI at any time to copy ready-to-use connection URLs:

* **Web UI / WebDAV / Cloudflare Tunnel:** `http://<SERVER_IP>:8090/`
* **macOS Finder / iOS Files / Infuse (SMB):** `smb://<SERVER_IP>/OmniDrive`
* **Windows Explorer (UNC Path):** `\\<SERVER_IP>\OmniDrive`
* **SFTP (FileZilla / Cyberduck / Termius):** `sftp://admin@<SERVER_IP>:2222/`
* **FTP (Standard FTP Clients):** `ftp://admin@<SERVER_IP>:2121/`
