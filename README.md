# Shanios – Custom Package Repository

This repository contains custom and patched PKGBUILDs used to build packages for [Shanios](https://github.com/shani8dev), an Arch-based Linux distribution.

All builds run inside a reproducible Docker container (`shrinivasvkumbhar/shani-builder`) so your host system is never polluted with build dependencies.

---

## Repository Layout

```
.
├── run_in_container.sh   # Generic wrapper – runs any command inside the build container
├── make_pkg.sh           # Convenience script – builds one or more packages
├── check-skip-checksums.sh  # Flags SKIP checksums on non-pinned sources
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

### 3 – Build everything

```bash
./make_pkg.sh --all
```

### 4 – Update checksums and build

Use `--updpkgsums` to run `updpkgsums` inside the container before `makepkg`. Useful after bumping a version or modifying sources.

```bash
# Update checksums, then build
./make_pkg.sh --updpkgsums shani-core

# Update checksums for every package, then build all
./make_pkg.sh --updpkgsums --all
```

The updated `PKGBUILD` is written back to your host immediately via the bind mount.

---

## Running Arbitrary Commands

`run_in_container.sh` is a generic wrapper around `docker run`. Pass any command and it executes inside the container with the repo bind-mounted.

```bash
# Open an interactive shell
./run_in_container.sh bash

# Run makepkg manually in a specific package dir
./run_in_container.sh bash -c "cd /build/filesystem && makepkg -s"

# Inspect the container environment
./run_in_container.sh env
```

---

## Checking for Missing Checksums

`sha256sums=('SKIP')` is only legitimate for a source whose content is already pinned some other way (a `git+`/`svn+`/`hg+`/`bzr+` VCS source, a local file shipped in the package's own directory, or a URL path containing a full commit hash). On a plain versioned tarball or a mutable-branch URL, `SKIP` means the download has no integrity check at all — this has slipped in unnoticed before.

```bash
# Check every package
./check-skip-checksums.sh --all

# Check specific packages
./check-skip-checksums.sh hplip-minimal shani-keyring
```

Exits non-zero if it finds a `SKIP` that isn't actually pinned. Runs on the host (no container needed) — it only sources each `PKGBUILD` to read its `source=`/`sha256sums=` arrays, it never runs `build()`/`package()`.

---

## Updating a pinned-commit package

If a `PKGBUILD` uses `_commit='<hash>'` for a `git+` source, **changing that
hash without also bumping `pkgrel` will silently fail to rebuild.**
`shani-builder`'s `pkg-builder.sh` skips any package whose
`pkgname-pkgver-pkgrel-arch` combination already exists in the repo — if
you only update `_commit`, the artifact filename doesn't change, so the
builder sees it's "already built" and never picks up the new commit.
Always bump `pkgrel` in the same change that updates `_commit`.

---

## Caching

| Host path | Container path | Purpose |
|---|---|---|
| `cache/pacman_cache/` | `/var/cache/pacman` | Avoids re-downloading pacman packages across builds |
| `cache/flatpak_data/` | `/var/lib/flatpak` | Persists flatpak data across builds |

Both directories are created automatically on first run.

---

## Package List

PKGBUILDs and accompanying files live at the repository root, each in their own directory (e.g., `shani-core/`, `shani-tools/`, `filesystem/`). Each directory contains a `PKGBUILD` and any associated patches or install scripts.

---

## Troubleshooting

**`docker: permission denied`**
Add your user to the docker group: `sudo usermod -aG docker $USER`, then log out and back in.

**`updpkgsums` fails with network errors inside the container**
The container uses `CUSTOM_MIRROR` for Arch packages. If the mirror is unreachable, edit `CUSTOM_MIRROR` in `run_in_container.sh`.

**Build fails with missing dependencies**
The script automatically syncs the pacman database before the first build. If dependencies are still missing, ensure the package directory exists and contains a `PKGBUILD`.

---

## Adding a New Package

1. Create a directory named after the package: `mkdir my-package/`
2. Write the `PKGBUILD` following the conventions of neighbouring packages:
   - `arch=('x86_64')`
   - Pin sources by commit/tag, not a moving branch
   - Prefer `source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")` style renaming so cached sources stay unique
3. If the package ships services/groups, add a `$pkgname.install` with
   idempotent `post_install`/`post_upgrade` hooks (guard `groupadd` with
   `getent`, guard `systemctl enable` — systemd makes re-enabling safe)
4. Generate checksums inside the container:

   ```bash
   ./make_pkg.sh --updpkgsums my-package
   ```
5. Build it: `./make_pkg.sh my-package` — the container produces the `.pkg.tar.zst` and publishes via `pkg-builder.sh` if credentials are configured
6. For metapackages that other profiles depend on, update the relevant `image_profiles/*/package-list.txt` in shani-install-media **in the same change**

### Review expectations

- No network access at package time beyond declared `source=`/`makedepends`
- `SKIP` checksums are accepted only for `-git`/`-nightly` packages where upstream has no stable tarballs; everything else pins real sums
- Install scripts must be idempotent and must not fail on upgrade paths (test `pacman -U` over an installed previous version)
