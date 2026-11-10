# Changelog

All notable changes to **OmniDrive Pro (Docker Edition)** are documented in this file.

## [1.0.29] - 2026-11-10
- **Standalone Linux Docker Port:** Ported **OmniDrive Pro** from Home Assistant OS Add-on to a standalone, multi-architecture Linux Docker container (`linux/amd64` & `linux/arm64`) running on official Alpine Linux `3.24` and Nginx `1.30.6-r0`.
- **Removed `bashio` Dependency:** Replaced Home Assistant `bashio` calls with a pure POSIX/Bash `entrypoint.sh` initializer supporting both Docker Environment Variables (`OMNI_USER`, `OMNI_PASS`, `SMB_ENABLED`, `SFTP_ENABLED`, `FTP_ENABLED`, `FTP_PASV_ADDRESS`) and persistent `/data/options.json` configuration.
- **Full Host Filesystem Access (`/host_system`):** Added automatic detection for `- /:/host_root:rw` mounts, exposing the entire Linux host filesystem under `/host_system` across Web UI, WebDAV, SMB, SFTP, and FTP.
- **Zero-Config `/mnt/*` Auto-Discovery:** Automatically links and provisions Samba shares for any host directory mounted under `/mnt/<name>` (such as `/DATA`, `/home`, `/etc`, `/opt`) without requiring manual configuration edits.
- **CasaOS & Portainer Integration:** Added OCI container metadata, `x-casaos` 1-click import definitions, and embedded `icon.png` for CasaOS dashboards and iOS/PWA home screen icons.
- **Automated CI/CD Upstream Tracking:** Added GitHub Actions workflows (`auto-update-base.yml` and `docker-publish.yml`) to automatically query official Alpine Linux `APKINDEX` packages daily, commit new Alpine/Nginx versions, and push multi-arch images to `ghcr.io`.

## [1.0.28] - 2026-11-10
- **Maintenance & Improvements:** Updated documentation and refined standalone Web UI layout spacing for Safari and mobile browsers.

## [1.0.20 - 1.0.27] - 2026-11-10
- **UI & Responsive Refinements:** Polished iOS Glassmorphism cards, header/footer layout spacing, and standalone logout button visibility when accessed outside an iframe.
- **Multi-Protocol Connect Hub:** Added interactive 1-tap copy cards for SMB (`445`), SFTP (`2222`), FTP (`2121`), and WebDAV (`8090`).

## [1.0.10 - 1.0.19] - 2026-11-10
- **Hybrid Auth & iOS Glass Login Page:** Introduced `login.html` with `HMAC-SHA256` 30-day session cookies for web browsers while preserving seamless HTTP Basic Auth for native OS WebDAV clients.
- **Multi-Protocol Engine:** Integrated Samba v3 (`smbd`), OpenSSH SFTP (`sshd`), and `vsftpd` alongside Nginx `dav-ext`.

## [1.0.2 - 1.0.9] - 2026-11-09
- **Pro System Suite:** Added integrated Web Terminal (`xterm.js`), Storage Analytics Donut Chart, 1-Tap Quick Zip Snapshot, Temporary Expiry Share Links (`/s/<token>`), and real-time Security Audit Log.
- **Advanced Viewers & IDE Enhancements:** Added `PDF.js` canvas viewer, Hex/Binary inspector, Apple Music-style background audio mini-player, Git status badges, and Ace Editor code minimap.

## [1.0.0] - 2026-11-08
- **Initial Release:** Launched core WebDAV Server & Cloud Code IDE with One Dark syntax highlighting, real-time YAML linting, Archive Inspector, and iOS Dark File Manager UI.
