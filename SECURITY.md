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
| HTTPS sources | `http://` sources are flagged; Secure-Boot-adjacent packages use `https://` |
| GPG signing | Packages signed before upload to `shani-repo` |

## Known Limitations

- **Mutable-tag false negative.** `check-skip-checksums.sh:80`
  `is_pinned_source()` treats any `git+` URL as pinned, even when it points at
  a mutable tag (`#tag=$pkgver`). A tag can move, making `SKIP` checksums
  unsafe. Verify refs are immutable (`#commit=<sha>`) before trusting the
  linter's pass.
- **No automated drift check.** `shani-keyring/PKGBUILD` checksums must be
  manually bumped when `shani-keyring` repo content changes. Nothing checks the
  two stay in sync automatically.

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
