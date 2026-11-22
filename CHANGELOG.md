# Changelog

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

---

## 1.0.32
_Released: 2026-11-22_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.31` ➡️ **`v1.0.32`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** `1.30.7-r0`
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r1`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.32` (`sha256:ba1b3b22be658751b6833fe8ae27dab2f0aa235495d68b46eba23fb5e4c22eb3`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Security & Core Engine:** Hardened RBAC (`admin`/`user`), enforced `allowed_users`/`read_only` isolation, fixed FTP symlink access, and added graceful shutdown.
- **Web UI & IDE:** Refined FancyIndex interface, Cloud Code IDE, and client UX.
- **Container Image:** Updated multi-arch Dockerfile build and healthcheck.
- **Compose Stack:** Updated Docker Compose template and environment options.

---

## 1.0.31
_Released: 2026-11-19_

### 📦 Component & Version Matrix
- **Docker Image Release:** Bumped from `v1.0.30` ➡️ **`v1.0.31`**
- **Supported Architectures:** `linux/amd64` & `linux/arm64` *(Multi-Arch GHCR Manifest)*
- **Alpine Base Image:** `Alpine 3.24`
- **Nginx Engine:** Updated from `1.30.6-r0` ➡️ **`1.30.7-r0`**
- **Protocol Stack:** `Samba 4.23.8-r0` • `OpenSSH 10.3_p1-r2` • `vsftpd 3.0.5-r3` • `Python 3.14.10-r1`

### 🔐 Package Integrity (GHCR Multi-Arch)
- **Image Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:1.0.31` (`sha256:1b53047bbee0c3659af84e3e0f52efd60f55f2dd3ffb1c5f967f34342066dede`)
- **Latest Tag:** `ghcr.io/boystyle2010/omnidrive-pro-docker:latest`

### 🚀 What's Changed
- **Upstream Base & Engines:** Refreshed Alpine (`3.24`), Nginx (`1.30.7-r0`), Samba (`4.23.8-r0`), OpenSSH (`10.3_p1-r2`), and vsftpd (`3.0.5-r3`) with latest security patches.
