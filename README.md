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

Create a `docker-compose.yml` file on your Linux server:

```yaml
services:
  omnidrive-pro:
    image: ghcr.io/boystyle2010/omnidrive-pro:latest
    container_name: omnidrive-pro
    restart: unless-stopped
    labels:
      icon: "https://raw.githubusercontent.com/boystyle2010/omnidrive-pro/main/icon.png"
    environment:
      - TZ=America/Denver
      - OMNI_USER=admin
      - OMNI_PASS=changeme_strong_password
      - SMB_ENABLED=true
      - SFTP_ENABLED=true
      - FTP_ENABLED=true
      - FANCY_UI=true
      - SHOW_DOTFILES=true
      # Replace with your Linux server's LAN IP so FTP Passive Mode works smoothly
      - FTP_PASV_ADDRESS=192.168.1.100
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
      - /:/host_root:rw

      # 3. ZERO-CONFIG SHORTCUTS (Any folder mounted to /mnt/<Name> appears on the home screen)
      - /DATA:/mnt/DATA
      - /home:/mnt/home
      - /etc:/mnt/etc
      - /opt:/mnt/opt
      - /var/log:/mnt/var_log
```

Start the container:

```bash
docker compose up -d
```

Open your browser and navigate to:
👉 **`http://<YOUR_SERVER_IP>:8090`**

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
      - FTP_PASV_ADDRESS=192.168.1.100
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
      icon: https://raw.githubusercontent.com/boystyle2010/omnidrive-pro/main/icon.png
      index: /
      port_map: "8090"
      scheme: http
      title:
        en_us: OmniDrive Pro
```

4. Verify your **Environment Variables** (`OMNI_USER`, `OMNI_PASS`, and `FTP_PASV_ADDRESS`) in the CasaOS UI form, then click **Install**.
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
| `FTP_PASV_ADDRESS`| *(empty)* | Host LAN IP address for FTP Passive data connections (`21000-21002`). |
| `MAX_UPLOAD_SIZE` | `0` | Max upload size (`0` = unlimited). |
| `SHOW_DOTFILES` | `true` | Show hidden files and folders starting with `.` (e.g., `.env`, `.gitignore`). |
| `SSL` | `false` | Set to `true` to enable native HTTPS using `/ssl/fullchain.pem` and `/ssl/privkey.pem`. |

> **Multi-User & Custom Share Configuration:** After the first run, you can edit `/data/options.json` directly (even from inside OmniDrive Pro's own Code Editor!) to add multiple user accounts or custom read-only share rules, then restart the container.

---

## 🔌 Client Connection Guide

Tap the **Connect** button in the OmniDrive Pro Web UI at any time to copy ready-to-use connection URLs:

* **Web UI / WebDAV / Cloudflare Tunnel:** `http://<SERVER_IP>:8090/`
* **macOS Finder / iOS Files / Infuse (SMB):** `smb://<SERVER_IP>/OmniDrive`
* **Windows Explorer (UNC Path):** `\\<SERVER_IP>\OmniDrive`
* **SFTP (FileZilla / Cyberduck / Termius):** `sftp://admin@<SERVER_IP>:2222/`
* **FTP (Standard FTP Clients):** `ftp://admin@<SERVER_IP>:2121/`
