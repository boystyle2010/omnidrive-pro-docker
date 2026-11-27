# Changelog

## 1.0.39
_Released: 2026-11-27_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.38` ➡️ **`v1.0.39`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.8-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r2`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.39` (`sha256:fc020d831d131ae0f29153c95c008b6f370bfe07e28953bb7be60b99284f0275`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Update:** fix: FTP never started - remove ssl_tlsv1_1 / ssl_tlsv1_2 (unknown to vsftpd 3.0.5)

---

## 1.0.38
_Released: 2026-11-27_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.37` ➡️ **`v1.0.38`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.8-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r2`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.38` (`sha256:6717e28ba2a416f50c1d5ad39620ee37688c4459b7313b8516a573661273b2b8`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Update:** fix(entrypoint): show why a supervised service (vsftpd, sshd, smbd) stopped instead of discarding its output

---

## 1.0.36
_Released: 2026-11-25_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.35` ➡️ **`v1.0.36`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.7-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r2`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.36` (`sha256:085961c24cd8a5787cf4da017546d308fb7ccf0fa0a23e48642c183abbe3ffae`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Update:** chore(release): v1.0.35 (Alpine 3.24 / Nginx 1.30.7-r0) [skip ci]
- **Security:** Rebuilt on the latest Alpine `3.24` security updates (Samba `4.23.8-r0`, OpenSSH `10.3_p1-r2`, vsftpd `3.0.5-r3`, OpenSSL, Python `3.14.10-r2`).

---

## 1.0.34
_Released: 2026-11-22_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.33` ➡️ **`v1.0.34`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.7-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r1`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.34` (`sha256:29ded861badff8196b19709a1cc643d6bbdf28c16cc46abdd6772c147b326149`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Update:** feat: OMNI_PASS is applied only when it changes, optional auto-removal from docker-compose.yml

---

## 1.0.33
_Released: 2026-11-22_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.32` ➡️ **`v1.0.33`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.7-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r1`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.33` (`sha256:c4fb002951fe2877e8cc8e9c40d93d5b71225d96eed2342d2eaf4b314f9139b7`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Update:** docs/ci: correct image name in README, clearer release notes for merged pull requests
