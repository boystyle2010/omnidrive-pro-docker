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
  - Mount `/` to `/host_root:rw` to inspect and edit **100% of your Linux server files** under `/host_system`.
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
  - **Security Audit Log:** Tracks logins, file modifications (`PUT`), deletions (`DELETE`), snapshots, and share-link downloads in real time.

---

## 🚀 Quick Start (Docker Compose)

> ⚠️ **Read before you start** — three things to change from the defaults:
> 1. **Change `OMNI_PASS`.** The default password is public. Anyone who guesses it gets a root-level terminal and full file access (see [Security Notes](#-security-notes)).
> 2. **Set `FTP_PASV_ADDRESS`** to your server's LAN IP *only if you use FTP* (find it with `hostname -I`). Not needed for Web UI, WebDAV, SMB or SFTP.
> 3. **Check that the ports are free** (`8090`, `445`, `2222`, `2121`, `21000-21002`). See [Troubleshooting](#-troubleshooting) if Docker reports `port is already allocated`.

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
      # !!! CHANGE THIS PASSWORD before exposing the service !!!
      - OMNI_USER=admin
      - OMNI_PASS=changeme_strong_password
      - SMB_ENABLED=true
      - SFTP_ENABLED=true
      - FTP_ENABLED=true
      - FANCY_UI=true
      - SHOW_DOTFILES=true
      # FTP Passive Mode only: uncomment and set this to the LAN IP of the
      # machine running Docker (find it with: hostname -I).
      # Without it, FTP clients may hang when listing folders.
      # Not needed for Web UI, WebDAV, SMB or SFTP.
      # - FTP_PASV_ADDRESS=192.168.1.100
    ports:
      - "8090:8090"               # Web UI, WebDAV & Share Links
      - "445:445"                 # SMB / Samba Server
      - "2222:2222"               # SFTP Server
      - "2121:2121"               # FTP Control Port
      - "21000-21002:21000-21002" # FTP Passive Data Ports
    volumes:
      # 1. OmniDrive Pro persistent config, audit logs & share links
      - ./data:/data
      - ./ssl:/ssl
      - ./backup:/backup
      - ./storage:/storage
      - ./media:/media
      - ./share:/share

      # 2. FULL HOST FILESYSTEM ACCESS (Appears as /host_system)
      #    WARNING: mounts the ENTIRE host filesystem read/write.
      #    Remove this line if you do not need full host access.
      - /:/host_root:rw

      # 3. ZERO-CONFIG SHORTCUTS (Any folder mounted to /mnt/<Name> appears on the home screen)
      #    Adjust or remove paths that do not exist on your system
      #    (e.g. /DATA exists on CasaOS/ZimaOS only).
      - /DATA:/mnt/DATA
      - /home:/mnt/home
      - /etc:/mnt/etc
      - /opt:/mnt/opt
      - /var/log:/mnt/var_log
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
      - type: bind
        source: /
        target: /host_root
      - type: bind
        source: /DATA
        target: /mnt/DATA
      - type: bind
        source: /home
        target: /mnt/home
      - type: bind
        source: /etc
        target: /mnt/etc
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
| `SSL` | `false` | Set to `true` to enable native HTTPS using `/ssl/fullchain.pem` and `/ssl/privkey.pem`. |

> **Multi-User & Custom Share Configuration:** After the first run, you can edit `/data/options.json` directly (even from inside OmniDrive Pro's own Code Editor!) to add multiple user accounts or custom read-only share rules, then restart the container.

---

> **Environment variables are re-applied on every start.** Changing `OMNI_USER` / `OMNI_PASS` in `docker-compose.yml` and recreating the container (`docker compose up -d`) overwrites the first user in `/data/options.json`.

---

## 🔒 Security Notes

OmniDrive Pro is powerful by design, so please harden it before exposing it beyond your home network:

- **Change the default password** (`changeme_strong_password`). Use a long, unique one.
- **The Web Terminal runs shell commands as root inside the container.** Combined with the `/:/host_root:rw` mount, anyone who logs in can read, modify or delete **any file on your host**. Remove the `/:/host_root:rw` line if you only need specific folders.
- **Do not publish ports directly to the internet.** Prefer a VPN (Tailscale / WireGuard) or a Cloudflare Zero Trust Tunnel with extra access control. If you must expose it, enable HTTPS (`SSL=true`) or terminate TLS at a reverse proxy.
- **Share links (`/s/<token>`) are public** to anyone who has the URL until they expire. Use the shortest expiry that works and revoke links you no longer need.
- **Only expose the protocols you use.** Set `SMB_ENABLED`, `SFTP_ENABLED` or `FTP_ENABLED` to `false` and remove their `ports:` lines when not needed. Plain FTP is **unencrypted** — use it on trusted LANs only; prefer SFTP or SMB.
- **Back up before editing** critical files (use the **Quick Zip** button).

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
