# Agent instructions — shani-pkgbuilds

This file applies to any AI coding assistant working in this repository
(Claude Code, opencode, Kilo Code, Cursor, Aider, or similar). Read this
before editing, and follow the verification steps before calling any change
done.

## What this repo is

Custom and patched PKGBUILDs for Shanios — every build runs inside the
reproducible `shani-builder` Docker container so the host is never
polluted with build dependencies. This is also where a package's `.install`
usually enables the service it ships, so a "missing service" bug reported
elsewhere often actually belongs here, not in `shani-settings` or an image
profile.

## Rule: a PKGBUILD that looks right and a PKGBUILD that builds are different claims

Don't consider a checksum, URL, or `prepare()`/`build()` change correct
because it reads correctly — actually run the real build. This repo has
shipped a real package (`hplip-minimal`) with `sha256sums=(SKIP ...)` on
its actual upstream tarball and an unverified installer executed at build
time; it looked like ordinary PKGBUILD boilerplate until someone actually
ran `check-skip-checksums.sh` against it.

## If you have Superpowers / oh-my-opencode / ultrawork / similar available

If your environment provides Claude Code's **Superpowers** plugin (TDD,
debugging, and verification-discipline skills), OpenCode's
**oh-my-opencode** (parallel/async subagents, LSP/AST tooling), an
**ultrawork**-style high-autonomy parallel execution mode, or an
equivalent skill/subagent framework in whatever tool you're running as —
use its parallel-subagent capability to build several changed PKGBUILDs
concurrently, and specifically for the corrupt-then-rebuild pattern below
(prove a checksum change actually rejects tampered content, not just that
it's present). Don't let a skill framework's plan-and-report output
substitute for actually running `makepkg`.

## Required verification for any PKGBUILD change

```bash
# Wired into pre-commit — catches SKIP on a non-VCS source, among other things
pre-commit run check-skip-checksums --all-files

# Actually build the package you touched, using the real builder container
# (run make_pkg.sh directly on the HOST — it invokes run_in_container.sh
# itself. Wrapping it as `./run_in_container.sh make_pkg.sh <pkg>` would
# resolve make_pkg.sh to $CONTAINER_WORK_DIR/make_pkg.sh and re-enter the
# runner inside the container, where the run_in_container.sh symlink target
# (../shani-install-media/) doesn't exist.)
./make_pkg.sh <package-name>
```

A build that completes is necessary but not sufficient — if you pinned or
changed a checksum, also **prove it actually verifies**: corrupt a local
copy of the source file, run the identical checksum/signature check the
PKGBUILD uses, and confirm it fails; then confirm the real, untampered
file passes. A checksum that's merely present but never actually
computed correctly gives false confidence.

## Things that have bitten this repo specifically

- **`git+` sources are not automatically "pinned" — FIXED in the checker,
  still true as a review habit.** `is_pinned_source()` now correctly
  requires `#commit=<40-hex-sha>` (a `#tag=$pkgver` no longer passes), and
  the extraction worker now checks all 8 makepkg checksum-array names, not
  just `sha256sums` — see the check-skip-checksums entry below for the
  full story (a real, previously-undetected gap, not just this one rule).
  Still worth knowing by hand: a tag can move upstream even when the
  PKGBUILD never changes, so prefer `#commit=` over `#tag=` when writing a
  new `git+` source rather than relying on the linter to catch it later.
- **A source over plain `http://` isn't meaningfully checksummed** if the
  checksum itself was only ever captured once by hand — prefer `https://`
  wherever upstream supports it, especially for anything in the
  Secure-Boot-adjacent trust chain (`shim-signed` and similar).
- **`run_in_container.sh` runtime check** — resolved via symlink to shani-install-media's copy which detects `--userns=keep-id` automatically. See `../shani-install-media/run_in_container.sh`.

## Audit-verified known issues (confirmed present)

- **check-skip-checksums false negatives — FIXED, and the real gap was
  bigger than documented (Med → both issues now closed).**
  `is_pinned_source()` (`check-skip-checksums.sh:76`) now only treats a
  `git+` source as pinned when its fragment is `#commit=<40-hex-sha>` —
  `#tag=`/no-fragment (mutable) no longer passes. Separately, and **not
  previously documented**: the `__extract` worker (`check-skip-checksums.sh:37`)
  hardcoded `sha256sums` as the only checksum array it ever inspected,
  silently skipping any package using `b2sums`/`sha512sums`/`sha1sums`/
  `md5sums` instead — confirmed 8 such packages exist in this repo
  (`lsb-release`, `brlaser`, `game-devices-udev`, `gsconnect`, all three
  `shani-desktop-*`, `shim-signed`). This meant `game-devices-udev`'s SKIP'd
  `b2sums` on a mutable `#tag=` source (the very case this script exists to
  catch) was **never actually checked by this tool at all** before now,
  regardless of the tag-vs-commit logic. Fixed by looping over all 8
  makepkg checksum-array names. Verified live: `./check-skip-checksums.sh --all`
  now correctly flags exactly `game-devices-udev` and `os-installer`
  (the two real, previously-undetected SKIP-on-mutable-tag cases) and
  nothing else — no new false positives against the other 39 packages.
  Both flagged packages were then actually fixed: pinned to the real commit
  each tag currently dereferences to (resolved live via
  `git ls-remote --tags`, not guessed) — `game-devices-udev` to
  `aaaf684043b33a330630335a3782b02ecf87a52e` (tag `1.0`), `os-installer` to
  `fc558178e79e4abd0408b296dc5e66b1ff3fdbdf` (tag `0.5.1`) — `pkgrel`
  bumped on both. `game-devices-udev` built completely for real
  (`makepkg -s`, full meson build + package(), verified against a writable
  scratch copy — see "runtime check before `--userns=keep-id`" below for
  why not a direct in-place build) and its `.SRCINFO` regenerated to match;
  `os-installer`'s pinned source was confirmed to actually clone at that
  commit (full build skipped — its GTK4/libadwaita/vte4 deps are unrelated
  to this fix and not worth installing just to prove a git checkout works).
- **foo2zjs-nightly firmware URL scheme — flipped twice; `http://` is the
  actually-correct state, verified by really running the drift check, not
  just by checking a scheme resolves.** An earlier pass switched all 26
  `_firmware` URLs (plus `url=`) from `http://` to `https://`, reasoning
  that HTTPS resolved and served byte-identical content to the existing
  checksums — true, but **not what actually matters here**: `prepare()`'s
  drift check doesn't care what scheme resolves, it diffs the hardcoded
  `_firmware` array text against a live `./listweb all` scrape (the exact
  same tool CI runs), and `listweb` — generated from upstream's own
  `getweb.in` template — emits `http://`, not `https://`. Switching to
  `https://` made every real CI build fail `prepare()` with "A failure
  occurred in prepare()", which is the failure that led to this
  correction. Confirmed by actually running `prepare()` for real inside
  the builder container against the live site both before and after:
  with `https://` it printed a fresh `_firmware=(...)` block (all
  `http://`, identical paths/order, scheme-only diff) and exited 1; after
  reverting all 26 URLs to `http://`, the identical real run completed
  with "Sources are ready" and no drift-check failure. Content is
  byte-identical either way (confirmed via sha256 on both schemes for
  `foo2hiperc/icm/okic301.tar.gz`), so existing checksums and `pkgrel`
  needed no changes — `.SRCINFO` regenerated via a real
  `makepkg --printsrcinfo` run and diffed to confirm the scheme was the
  only change. **Lesson for next time:** when a PKGBUILD has a live
  drift/consistency check like this one, verify a URL-scheme change
  against what the check itself compares against, not just against
  "does this URL work" — the two can disagree.
- **`pkg_name` interpolation — FIXED.** `make_pkg.sh:96` built
  `BUILD_CMD="...cd /build/${pkg_name} && makepkg ..."` with `pkg_name`
  (a caller-supplied CLI argument, or a `find`-derived name for `--all`)
  interpolated unquoted directly into a string later executed via
  `bash -c "$BUILD_CMD"` inside the container — a real command-injection
  shape, not just a style nit. Verified both the bug and the fix directly:
  before the fix, `pkg_name='foo; touch /tmp/INJECTED'` produced a
  `BUILD_CMD` that executed the injected `touch` when run through
  `bash -c`; after wrapping with `printf %q`, the same input becomes a
  single shell-quoted token and `cd` correctly fails with "No such file or
  directory" instead — confirmed `/tmp/INJECTED` is never created. Also
  fixes a real (if less severe) pre-existing bug: any legitimate package
  directory name containing a space would have silently broken this same
  line before.
- **CI status.** No CI workflows — verification via pre-commit hooks only.
- **Stale `.SRCINFO` in 10 of 17 tracked packages — FIXED.** Was: confirmed by actually running `makepkg --printsrcinfo` and diffing against the committed file (real mismatch — `filesystem/.SRCINFO` still described the pre-rebrand "Base Arch Linux files" while `PKGBUILD` was "Base Shani OS files", plus `foo2zjs-nightly`, `game-devices-udev`, `gnome-shell-extension-gsconnect`, `hplip-minimal`, `lsb-release`, `plasma-setup-git`, `shim-signed`, `snapd`, `waydroid-helper`). All 10 regenerated via a real `makepkg --printsrcinfo` run in the builder container (`--user builduser`, a writable scratch copy to work around real-Docker's lack of `--userns=keep-id`) and committed.
- **19 of 41 PKGBUILDs have no `url=` — FIXED.** Was: confirmed by grep and independently by `namcap` ("E/W: Missing url") on `shani-core`/`shani-network`. All 19 (`desktop-entry-hider`, `shani-accessibility`, `shani-bluetooth`, `shani-core`, `shani-desktop-cosmic`, `shani-desktop-gnome`, `shani-desktop-plasma`, `shani-fonts`, `shani-multimedia`, `shani-network`, `shani-peripherals`, `shani-printer`, `shani-scanner`, `shani-storage`, `shani-tools-extra`, `shani-tools-network`, `shani-tools`, `shani-video-guest`, `shani-video`) now have `url="https://github.com/shani8dev/shani-pkgbuilds/tree/main/<pkgname>"` (they're first-party metapackages with no separate upstream repo, so their own subdirectory in this repo is the correct URL — matching the convention `os-installer-config` already used), `pkgrel` bumped on each.
- **3 PKGBUILDs have no `# Maintainer:` line — FIXED.** Was: `desktop-entry-hider/PKGBUILD:1`, `plasma-setup-git/PKGBUILD:1`, `shani-deploy/PKGBUILD:1` (namcap-confirmed on the last). All 3 now have the standard `# Maintainer:` line, `pkgrel` bumped.

- **`os-installer-config` arch mismatch — FIXED.** Was `arch=('x86_64')` with no compiled output (`namcap`: "W: No ELF files and not an 'any' package"); now `arch=('any')`.
- **`os-installer-config` undeclared script runtime deps — FIXED.** `depends=('bash' 'python' 'python-yaml')` added (needed by `etc/os-installer/po/config_to_pot.py` and the shell scripts under `etc/os-installer/scripts/`).
- **os-installer-git missing `git` makedepends — FIXED.** `makedepends` now includes `git`, matching the `git+` `source=`.
- **Non-SPDX `license=()` identifiers across 27 PKGBUILDs — FIXED.** Was: `namcap` flags this at ERROR level (confirmed on `os-installer-config`: "E: BSD is not a valid SPDX license identifier"). Each of the 27 was researched individually (not blanket-substituted) to find the package's *actual* license, not just reformat the legacy shorthand: `os-installer-config` → `BSD-3-Clause` (verified — this repo's own local `LICENSE` file is BSD-3-Clause, contradicting the PKGBUILD's bare `'BSD'`); `lsb-release` → `GPL-2.0-or-later` (Arch's own official `extra` package DB already uses this exact identifier for the same package); `plasma6-applets-window-title` → `GPL-2.0-only` (upstream's real LICENSE file is plain GPLv2 with no explicit "-or-later" declaration found anywhere); `systemd-oomd-defaults` → `LGPL-2.1-or-later` (systemd's own README states this exact identifier for all its code); `os-installer`/`os-installer-git` → `GPL-3.0-or-later` (GNOME upstream's `meson.build` explicitly declares `license: 'GPL-3.0-or-later'`); `snapd` → `GPL-3.0-only` (confirmed via an actual per-file copyright header in snapd's own source — "under the terms of the GNU General Public License version 3", no "or later" clause — not just the ambiguous generic COPYING boilerplate, which contains that phrase regardless of the project's real choice); `shani-deploy` and the 19 `shani-*` meta-packages → `GPL-3.0-only` (first-party, matches this repo's own top-level `LICENSE` and no explicit "-or-later" declaration exists anywhere in the ecosystem). `.SRCINFO` regenerated for the 3 affected packages that track one (`lsb-release`, `plasma6-applets-window-title`, `snapd` — diffed against the pre-change file each time to confirm the license line was the *only* change) via a real `makepkg --printsrcinfo` run in the builder container.
- **game-devices-udev lost GPG tag verification — FIXED, non-obviously.** Was: `source=("git+${url}.git#tag=$pkgver" ...)` had been changed to `#commit=<40-hex-sha>` in an earlier fix for a *different* real problem (a `#tag=` reference can be force-moved upstream without this PKGBUILD ever changing — `check-skip-checksums.sh` correctly flags this), but that fix accidentally dropped `validpgpkeys` and the `?signed` URL suffix entirely, leaving zero cryptographic verification. The two fixes looked mutually exclusive (makepkg's git-source PGP verification is normally tied to `#tag=`, not `#commit=`) — but verified live, `?signed` **does** work with a `#commit=<sha>` fragment too: `source=("git+${url}.git?signed#commit=$_commit" ...)` plus `validpgpkeys=('6E58E886A8E07538A2485FAED6A4F386B4881229')` gets both properties at once (immutable commit pin *and* real GPG verification), confirmed via an actual `makepkg --nobuild --nodeps` run in the builder container: "Verifying source file signatures with gpg... game-devices-udev git repo ... Passed (WARNING: the key has expired.)". The key genuinely is expired (`git verify-tag`/`git verify-commit` against the real upstream repo both return "Good signature ... [expired]", not a wrong/forged key — almost certainly why this toggled back and forth across many prior commits) — but makepkg treats an expired key as a warning, not a hard failure, so this is still strictly better than the unverified SKIP state it replaces. Also ran a full real `makepkg -f --nodeps` (not just `--nobuild`) to confirm the package actually still builds end-to-end with this source form; re-ran `check-skip-checksums.sh --all` afterward to confirm nothing else regressed.

- **The `trailing-whitespace` pre-commit hook corrupts `.patch` files — FIXED (root cause of the escpr2 "Hunk #3 FAILED" mystery).** In a unified diff, a context line is `<SPACE>content`; a whitespace-only context line is *exactly one space*. The hook trims it as "trailing whitespace", turning the line into an empty string — which `patch` then rejects, breaking hunk parsing (the escpr2 `prepare()` failure was "Hunk #3 FAILED at 459", and its vendored `bug_x86_64.patch` is whitespace-sensitive: sha256 `57c7a32b…` applies cleanly, the trimmed variant `f68afef0…` doesn't). Proven: the successful full build at 11:52:27 used the good file (`Hunk #3 succeeded at 462 (offset 3 lines)`), then a `pre-commit run --all-files` at 11:52:55 silently re-trimmed it. Fix: `.pre-commit-config.yaml` now has `exclude: '\.patch$'` on that hook. Note: as of this fix, several *other* working-tree `.patch` files show the same whitespace-only drift vs HEAD (`splix/*`, `os-installer-git/*`, `cnijfilter2/*`, `foo2zjs-nightly/*`, `hplip-minimal/*`, `lsb-release/*`, `plasma6-applets-window-title/41.patch` — verified whitespace-only via `git diff --ignore-all-space`) — treat them as suspect (hook-trimmed, possibly breaking their packages' builds), don't blindly commit them.
- **shani-desktop-cosmic depended on a nonexistent package — FIXED.**
  `shani-desktop-cosmic/PKGBUILD`'s `depends=()` listed `gvfs-google`,
  which is not a real Arch package (confirmed via `pacman -Ss "^gvfs"`
  inside the actual builder image — the real list is `gvfs`,
  `gvfs-afc`, `gvfs-dnssd`, `gvfs-goa`, `gvfs-gphoto2`, `gvfs-mtp`,
  `gvfs-nfs`, `gvfs-onedrive`, `gvfs-smb`, `gvfs-wsdd`, no `-google`
  variant), causing every CI build to fail with "target not found:
  gvfs-google". Confirmed it was a stray erroneous entry, not an
  intentional third-party AUR dependency the packager forgot to declare
  as such, by diffing against the otherwise-identical
  `shani-desktop-gnome/PKGBUILD` dependency list, which has every other
  `gvfs-*` entry but not this one. Removed; `pkgrel` left unchanged since
  no artifact was ever actually published at that `pkgrel` (the build had
  always failed).
- **game-devices-udev "unknown public key" CI failure — root cause was in
  `shani-builder`, not here; this PKGBUILD was already correct.** Worth
  cross-referencing so a future pass doesn't re-diagnose this file: the
  `validpgpkeys=('6E58E886A8E07538A2485FAED6A4F386B4881229')` entry
  documented in the "game-devices-udev lost GPG tag verification" fix
  above is genuinely correct (its trailing 16 hex chars match the CI
  error's "unknown public key D6A4F386B4881229" exactly) — the actual gap
  was that nothing in `shani-builder/pkg-builder.sh` ever imported a
  PKGBUILD's `validpgpkeys` into the build container's keyring before
  `makepkg` ran. Fixed there, generally, not by touching this PKGBUILD —
  see `shani-builder/AUDIT-HISTORY.md`.

**Still open (don't re-verify these as if they were new — they're already confirmed, just not yet fixed):**

- **shani-settings pkgrel never reset after a pkgver bump (Med).** `shani-settings/PKGBUILD:4-5` (currently `pkgver=0.0.5`, `pkgrel=40`) — confirmed via `git log -p`: commit `40152de` (2025-02-09) bumped `pkgver` 0.0.4→0.0.5 while leaving `pkgrel` at 2 instead of resetting to 1; it has climbed to 40 since, still under the same `pkgver=0.0.5`, without ever resetting.
- **`brlaser-debug`/`splix-debug` broken build-id symlink (Low).** Confirmed by actually building both packages and running `namcap` on the result: "E: Symlink (usr/lib/debug/.build-id/...) points to non-existing ../../../cups/filter/rastertobrlaser" (and the same for splix's `rastertoqpdl`/`pstoqpdl`). makepkg's auto-generated `-debug` split package computes the build-id symlink relative path assuming a standard `/usr/bin`-style install location; it breaks for a CUPS filter binary under `/usr/lib/cups/filter/`. Likely affects any other CUPS-filter package here that produces a `-debug` split (e.g. `cnijfilter2`, `hplip-minimal`, `foo2zjs-nightly`) — not individually re-verified. Cosmetic (only affects the optional debug package), not the main package.

## This repo is usually where a service actually gets enabled — check here first

Before assuming a package or systemd service is "missing" from a
`shani-install-media` image profile, check **this repo** first:
`<pkg>/PKGBUILD`'s `depends=()` for transitive packages (a profile's
`package-list.txt` only lists top-level meta-packages like `shani-network`/
`shani-core` — the real dependency is one level down, in here) and
`<pkg>/<pkg>.install`'s `post_install`/`post_upgrade` for `systemctl enable`
calls — this is where this project actually turns services on, not in
`shani-install-media`'s profile customization scripts. See
`shani-install-media/AGENTS.md`'s "Before claiming a package/service is
missing" section for the full five-layer chain and the real incident that
established this rule, and `shani-settings/AGENTS.md`'s "Where a given
config file actually belongs" for where DE-specific vs. profile-agnostic
config should live.

## Cross-repo impact — check before calling a fix complete

Every `shani-*` first-party package here (`shani-deploy`, `shani-settings`,
`shani-keyring`, `shani-fonts`, etc.) packages the *actual source repo* of
the same name — if that source repo's file layout, install paths, or
version changes, this repo's matching PKGBUILD needs a checksum/`pkgrel`
bump to match, or the packaged artifact silently drifts from what's
actually in the source repo. There is currently no automated check that
catches this drift — treat "did I update the source repo without touching
its PKGBUILD here" as a real, unflagged failure mode, not a hypothetical.

`shani-keyring/PKGBUILD` specifically must stay in sync with the sibling
`shani-keyring` repo's actual key/trust files — a checksum here that
doesn't match that repo's current content breaks every clean install.

`run_in_container.sh` is a symlink to `shani-install-media/run_in_container.sh` — see that repo's `AGENTS.md` for the full script. The symlink uses `BASH_SOURCE`-aware `HOST_WORK_DIR` detection so bind-mounts resolve to shani-pkgbuilds's directory. Any fix to shani-install-media's copy automatically applies here.

## Where things are documented

`README.md` for the build model, `SECURITY.md` for the trust
expectations. `check-skip-checksums.sh --help` explains its own false-negative
shape — read it before assuming a package that passes the linter is
actually safe.
