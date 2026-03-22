# Shani OS – Custom Package Repository

This repository contains custom and patched PKGBUILDs used to build packages for [Shani OS](https://github.com/shaniOS), an Arch-based Linux distribution.

All builds run inside a reproducible Docker container (`shrinivasvkumbhar/shani-builder`) so your host system is never polluted with build dependencies.

---

## Repository Layout

```
.
├── run_in_container.sh   # Generic wrapper – runs any command inside the build container
├── make_pkg.sh           # Convenience script – builds one or more packages
├── <package-name>/
│   ├── PKGBUILD
│   └── *.patch / *.install / other sources
└── cache/
    ├── pacman_cache/     # Shared pacman package cache (auto-created)
    └── flatpak_data/     # Shared flatpak data (auto-created)
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker** | Must be running; your user must be in the `docker` group |
| **Docker image** | `docker pull shrinivasvkumbhar/shani-builder` |
| Bash 4+ | Ships with every modern Linux distro |

---

## Quick Start

### 1 – Build a single package

```bash
./make_pkg.sh shani-core
```

Built `.pkg.tar.zst` files appear inside the package subdirectory (bind-mounted back from the container).

### 2 – Build multiple packages

```bash
./make_pkg.sh shani-core shani-tools shani-fonts
```

### 3 – Sync the pacman DB first, then build

Use `--sync` whenever you want to refresh the container's package database before building (recommended after a long gap or when upstream packages have changed).

```bash
./make_pkg.sh --sync shani-core
```

### 4 – Build everything

```bash
./make_pkg.sh --all
```

Combine with `--sync` to refresh the DB once before the full build:

```bash
./make_pkg.sh --sync --all
```

### 5 – Update checksums and build

Use `--updpkgsums` to run `updpkgsums` inside the container before `makepkg`. Useful after bumping a version or modifying sources.

```bash
# Update checksums, then build
./make_pkg.sh --updpkgsums shani-core

# Sync DB + update checksums + build
./make_pkg.sh --sync --updpkgsums shani-core

# Update checksums for every package, then build all
./make_pkg.sh --updpkgsums --all
```

The updated `PKGBUILD` is written back to your host immediately via the bind mount.

---

---

## Running Arbitrary Commands

`run_in_container.sh` is a generic wrapper around `docker run`. Pass any command and it executes inside the container with the repo bind-mounted.

```bash
# Open an interactive shell
./run_in_container.sh bash

# Run makepkg manually in a specific package dir
./run_in_container.sh bash -c "cd /home/builduser/build/filesystem && makepkg -s"

# Inspect the container environment
./run_in_container.sh env
```

---

## Caching

| Host path | Container path | Purpose |
|---|---|---|
| `cache/pacman_cache/` | `/var/cache/pacman` | Avoids re-downloading pacman packages across builds |
| `cache/flatpak_data/` | `/var/lib/flatpak` | Persists flatpak data across builds |

Both directories are created automatically on first run.

---

## Package List

| Package | Description |
|---|---|
| `brlaser` | Brother laser printer driver |
| `cnijfilter2` | Canon inkjet printer driver |
| `desktop-entry-hider` | Hide desktop entries via config |
| `epson-inkjet-printer-escpr2` | Epson ESC/P-R 2 printer driver |
| `filesystem` | Shani OS base filesystem & branding |
| `foo2zjs-nightly` | foo2zjs printer driver (nightly) |
| `game-devices-udev` | udev rules for game controllers |
| `gnome-shell-extension-gsconnect` | GSConnect GNOME extension |
| `hplip-minimal` | HP printing/scanning support (minimal) |
| `lsb-release` | LSB release identification |
| `os-installer` | OS installer frontend |
| `os-installer-config` | Shani OS installer configuration |
| `os-installer-git` | OS installer (git version) |
| `plasma6-applets-window-title` | KDE Plasma window title applet |
| `plasma-setup-git` | Shani KDE Plasma setup |
| `shani-accessibility` | Accessibility packages meta |
| `shani-bluetooth` | Bluetooth support meta |
| `shani-core` | Core system meta-package |
| `shani-deploy` | Deployment tooling |
| `shani-desktop-cosmic` | COSMIC desktop meta |
| `shani-desktop-gnome` | GNOME desktop meta |
| `shani-desktop-plasma` | KDE Plasma desktop meta |
| `shani-dracut-secureboot` | Dracut + Secure Boot integration |
| `shani-fonts` | Font collection (Noto, emoji, Indian) |
| `shani-keyring` | Shani OS signing keyring |
| `shani-multimedia` | Multimedia codecs meta |
| `shani-network` | Network tools meta |
| `shani-peripherals` | Peripheral support meta |
| `shani-printer` | Printer support meta |
| `shani-scanner` | Scanner support meta |
| `shani-settings` | System settings meta |
| `shani-storage` | Storage tools meta |
| `shani-tools` | Core tools meta |
| `shani-tools-extra` | Extra tools meta |
| `shani-tools-network` | Network tools meta |
| `shani-video` | Video drivers meta |
| `shani-video-guest` | VM guest video drivers meta |
| `shim-signed` | Signed UEFI shim for Secure Boot |
| `snapd` | Snap package daemon |
| `systemd-oomd-defaults` | systemd-oomd default config |
| `waydroid-helper` | Waydroid setup helper |

---

## Troubleshooting

**`docker: permission denied`**
Add your user to the docker group: `sudo usermod -aG docker $USER`, then log out and back in.

**`updpkgsums` fails with network errors inside the container**
The container uses `CUSTOM_MIRROR` for Arch packages. If the mirror is unreachable, edit `CUSTOM_MIRROR` in `run_in_container.sh`.

**Build fails with missing dependencies**
Run with `--sync` to refresh the package database: `./make_pkg.sh --sync <pkg>`.

