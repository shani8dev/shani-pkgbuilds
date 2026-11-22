# Security Policy

## Trust Model

`shani-pkgbuilds` is the Arch Linux package build and publish pipeline. It
operates under a **checksum-enforced, key-rooted** trust model:

- Every package is built from a PKGBUILD with **real `sha256sums`** on all
  non-VCS sources.
- The `shani-keyring` repo is the pacman trust root — every first-party package
  is signed and every client verifies against `shani.gpg`.
- `check-skip-checksums.sh` lints PKGBUILDs for `SKIP` on non-VCS sources
  (wired into pre-commit).

## Key Security Mechanisms

| Mechanism | Implementation |
|-----------|----------------|
| Checksum linter | `check-skip-checksums.sh` — flags `SKIP` on non-VCS sources |
| Real checksums | Upstream tarballs carry pinned `sha256sums` (not `SKIP`) |
| HTTPS sources | Plain `http://` is not flagged by this repo (e.g. `foo2zjs-nightly` uses it to match upstream drift); prefer `https://` |
| GPG signing | Packages signed before upload to `shani-repo` |

## Known Limitations

- **Mutable-tag sources still need care.** `check-skip-checksums.sh` now
  requires `#commit=<40-hex>` for a `git+` source to count as pinned —
  `#tag=` with `SKIP` is flagged. Tags can move, so prefer commit pins.
- **Keyring drift is checked.** A `check-keyring-sync` pre-commit hook
  (`scripts/check-keyring-sync.sh`) and the CI checksum scan
  (`.github/workflows/security.yml`) cover `shani-keyring` checksum drift.

## Reporting a Vulnerability

If you discover a security vulnerability in any Shanios project, please report it
responsibly by opening a private security advisory on GitHub.

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 72 hours and provide a detailed response
within 7 days. Thank you for helping keep Shanios secure.
