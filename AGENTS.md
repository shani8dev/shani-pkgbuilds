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

## Empirical verification (mandatory)

**Reading code is analysis; running code is verification.** A change is not
verified by reading the diff, running `bash -n`, or confirming it "looks
correct." It is verified by observing the actual behavior of the real
thing in the real environment — built, served, deployed, signed, running.
If you haven't seen it work (or fail) for real, it isn't verified.

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

### Container runs should mount the pacman cache

`shani-desktop-plasma/tests/plasma-session.sh` needs a full Plasma desktop in
the container (`plasma-desktop`, `kwin-x11`, `dolphin`, `konsole`, `yakuake`,
`gtk3-demos`, …) — roughly 2.6G installed. Mounting the cache turns that into
a cache-hit install: **measured 2026-09-26, a from-scratch run went from ~2G
of downloads to 681 MiB** with the caches mounted. Mount `cache/pacman_cache/`
(or the merged cache described in the parent `AGENTS.md`) at
`/var/cache/pacman/pkg`.

Two habits that cut the cost further, both learned the hard way:
- **Run every look/variant in one container.** The harness re-seeds a fresh
  `HOME` per argument and restarts Xvfb, so `Saturn-Dark`, `Saturn` and
  `Saturn-Twilight` are independent — install once, run all three, instead of
  paying the install per variant.
- **Mount the output directory.** `plasma-session.sh` writes screenshots to
  its `out-dir` argument (default `/tmp/plasma-shots`), which is *inside* the
  container. With `--rm` those are lost; pass a mounted path and the images
  survive. This actually happened — a baseline was captured and the
  screenshots went to an unmounted `/tmp` and were discarded on exit.
- Check whether `.pkg.tar.zst` already exists and is newer than the newest
  source before rebuilding, and use `pacman -Si` (sync db) rather than
  `pacman -Q` (installed) when checking a version in a fresh container — `-Q`
  returns empty and silent.

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

## Commit discipline

Before composing a commit message, run `git log --oneline -20` (and `git
log -5 -- <touched paths>` for the files you changed) and match the
existing style — subject shape, scope prefixes, body detail level —
rather than writing in a generic format.

## Boundaries

- ✅ **Always**: actually run `makepkg`/`./make_pkg.sh <pkg>` for any
  touched PKGBUILD, and if a checksum/signature changed, corrupt a local
  copy first to prove the check actually rejects tampering (see "Rule"
  above).
- ⚠️ **Ask first**: running a blanket formatter/whitespace-trimmer across
  this repo. The `trailing-whitespace` pre-commit hook already corrupted
  `.patch` files once (a whitespace-only context line in a unified diff is
  meaningful, not trailing noise) — several `.patch` files still show this
  drift as of this writing (see below); don't re-trigger the same class of
  breakage by hand.
- 🚫 **Never**: interpolate a caller-supplied or `find`-derived value
  (package name, path) unquoted into a string later run via `bash -c` —
  `make_pkg.sh`'s `pkg_name` injection (fixed below) is the exact shape to
  avoid; use `printf %q` or an array, not string concatenation.
- 🚫 **Never**: delete or skip a failing test to make a build/CI pass — fix the underlying code, not the test. A red test is signal; silencing it destroys the signal, not the bug.

## Audit-verified known issues (confirmed present)

- **`adbf925` (a shani-desktop-plasma commit) silently reverted two unrelated
  fixes — RESTORED (2026-09-23).** It swept in stale copies of
  `shani-keyring/PKGBUILD` (dropping `ca329bd`'s `depends=(bash gnupg)`, so in
  pacstrap the keyring's scriptlet `execv` failed again and the shani key was
  never populated - the plasma CI build log shows "call to execv failed") and
  `shani-tools-network/shani-tools-network.install` (back to the nonexistent
  `arpwatch.service`; Arch ships only `arpwatch@.service`). Both restored from
  their fixing commits (`shani-keyring` 20241020-5, `shani-tools-network`
  1.2-15, above the published -4/-14) and built for real. When committing a
  package, `git diff --stat` the whole tree first - this is how unrelated
  packages get reverted. Open: `arpwatch@eth0` only works on legacy interface
  names (most machines use `enp*`/`wlp*`).

- **shani-desktop-plasma theming — 12 real bugs FIXED (2026-09-23), all found
  and verified in a real kwin_x11 + plasmashell session
  (`shani-desktop-plasma/tests/plasma-session.sh`, run in an Arch container
  with the package at `/pkg`), not by reading configs:**
  (1) `BlurStrength=40` in skel/LnF/theme-sync: KWin indexes a 15-entry table
  with it unchecked (`blur.cpp`, `numOfBlurSteps = 15`), so KWin crash-looped
  as soon as blur rendered. Now 15; theme-sync clamps existing `>15`; checker rule.
  (2) Kvantum SVGs were swapped (light theme drew dark art). (3) Kvantum
  configs had lost 35 of 47 widget sections and upstream's `opaque=` app
  list; now generated by `build-kvantum.py` from vendored MacTahoe
  (`kvantum-upstream/`, commit `cbf6a1f`, LGPL-3.0); user-facing theme text
  is Saturn's, the upstream attribution is in
  `usr/share/licenses/shani-desktop-plasma/THIRD-PARTY` (keep it: LGPL). (4) Kvantum is read from
  `~/.config/Kvantum/kvantum.kvconfig`; theme-sync's fallback and the greeter
  wrote `kvantum.kvconfig` / `kdedefaults/`, which it never reads.
  (5) LnF `[Wallpaper] Image=` must be a wallpaper *package name*
  (plasma-workspace `DefaultWallpaper`); a `file://` URL fell through to
  stock "Next". Now `Saturn` / new `Saturn-Twilight` package. (6) Saturn and
  Saturn-Twilight's `layout.js`, `Splash.qml`, splash images and previews were
  symlinks out of their package, which KPackage ignores: no Shani panel/dock,
  no splash. Now copies; checker rule. (7) Shared `layout.js` forced
  `theme='Saturn'` on the dark looks. (8) Panel launcher icon
  `start-here-shani` was unreachable (moved to hicolor). (9) Greeter mixed
  light/dark values and didn't chown its Kvantum file. (10) **The splash never
  loaded**: `Behavior on progress` targets `Image.progress` (read-only), so
  QML rejected the whole file and KSplash showed nothing. Rewritten (frosted
  wallpaper baked by `build-splash.py`, no runtime shader); check any edit
  with `tests/render-splash.py` (loads it in the QML engine, fails on any
  error). (11) Saturn-Twilight now matches Breeze Twilight: light apps
  (Saturn colours/Kvantum/icons/GTK), dark Saturn-Dark Plasma style.
  (12) **Konsole/Yakuake never used the Saturn terminal colours**: the skel
  profile (and theme-sync) put `ColorScheme=` under `[General]`; Konsole
  reads it from `[Appearance]` only. Moved; theme-sync migrates old
  profiles; checker rule.
  (13) **Yakuake printed `Could not find '', starting '/usr/bin/bash' instead.
  Please check your profile settings.` — FIXED (2026-09-26), by pinning
  `Command=/usr/bin/fish` in the skel `shani.profile`. The skel profile set
  **no** `Command=`, under a comment claiming "Konsole runs the login shell
  (zsh by default), so chsh works" — that is wrong. Konsole/Yakuake do not
  fall back to the login shell: `Profile::Command` is *inherited* from the
  built-in profile, whose value is `defaultShell() = qgetenv("SHELL")` (konsole
  `Profile.cpp`). With no `$SHELL` in the environment (systemd unit, bare
  `ExecStart=`, non-login `su`) that is empty, so `Session::run()` warns and
  silently runs bash, ignoring the user's real shell. The warning is the
  *symptom*; the same condition also mis-runs the shell, so it is not
  cosmetic. `fish` is the shell and is a `shani-settings` dependency, not
  this package's — safe because only the `plasma` profile installs
  `shani-desktop-plasma` and that profile lists `shani-settings` in
  `Packages-Base` (verified; the `server` profile omits `shani-settings` but
  also never installs this package). Two checker rules now prevent the
  regression, both verified RED→GREEN: every shipped `*.profile` must set
  `Command=`, and `yakuakerc`/`konsolerc` `DefaultProfile` must resolve to a
  shipped profile. **The skel fix alone would have left every existing
  install broken** — it only reaches new users — so `shani-theme-sync.sh`
  now writes `Command=/usr/bin/fish` into an existing profile when the key
  is absent, alongside the `ColorScheme`/`Skin` migrations already there. It
  writes only when absent, so a shell the user chose is never clobbered.
  Verified against the shipped block (not a rewrite): repairs an old profile,
  is idempotent on re-run, and preserves a user's `/usr/bin/zsh`. That second one matters because `DefaultProfile` is
  resolved by konsole's `ProfileManager` under
  `GenericDataLocation/konsole` (`~/.local/share/konsole`,
  `/usr/share/konsole`) — **not** a `yakuake/profiles` directory — and a
  dangling name leaves konsole's built-in profile in place with no error at
  all, which is how this survived a green `check-package.py`.
  **Palette:** one neutral set for everything
  (`saturn_palette.py`: night-sky indigo dark / cream light, coral accent
  kept, harsh neon-teal "positive" -> mint), applied by `build-palette.py`
  (colour schemes, Konsole, Kvantum art) and `build-kvantum.py`; idempotent,
  gated by `check-contrast.py`. `shani-cassini` uses the same values.
  **Window decoration:** Saturn/Saturn-Dark Aurorae **v2** themes
  (`library=org.kde.kwin.aurorae.v2`, generated by `build-aurorae.py`)
  replace Breeze (hard-coded ~5 px corners) and Utterly-Round's Aurorae (no
  shadow: Aurorae's shadow is whatever the `decoration-*` frame paints in its
  padding). 12 px corners, header-colour title bar, measured Breeze-depth
  shadow, every button (`ButtonsOnLeft=XIA`, `ButtonsOnRight=SFBLHM`;
  on-all-desktops only shows with >1 virtual desktop - KWin's rule). Draw
  hairlines as filled shapes, never strokes: a stroke's half pixel changes
  the element bounds FrameSvg takes margins from, and QtSvg has no clipPath.
  Rounded **bottom** corners: KWin only clips app content to a radius the
  decoration reports (`setBorderRadius()`; Breeze and Klassy do, Aurorae
  never does), so the Saturn themes draw them with a 6 px frame round the
  client (`BorderLeft/Right/Bottom=6`) whose outer corners carry the 12 px
  curve; the content's own corners stay square inside it (chosen over
  shipping a patched Aurorae package).
  **Dead KWin effect config:** most `Effect-*` keys in skel/LnF/theme-sync
  were never read by KWin (checked against kwin's kcfg/main.xml): `enabled=`
  in effect groups (effects switch on in `[Plugins]`), all of
  `Effect-overview`/`Effect-windowaperture`/`Effect-backgroundcontrast`,
  magiclamp `duration` (real key `AnimationDuration`). Removed; validate new
  effect keys against kwin's schema before adding them.
  **Panel:** the window-buttons applet (0.14.0) can't render Aurorae SVG
  themes on Plasma 6.7 - it only treats plugin `org.kde.kwin.aurorae` as
  Aurorae, but SVG themes are now listed by `org.kde.kwin.aurorae.v2` (v1
  lists only QML themes) - so maximized windows show Breeze's buttons in the
  panel. Accepted by the maintainer (over keeping title bars or patching the
  applet); it follows the current decoration so a v2-aware release fixes it.
  The fix already exists upstream as open PR #31 ("Plasma 6.6 Compatibility",
  moodyhunter/applet-window-buttons6, recognises `org.kde.kwin.aurorae.v2`);
  Arch's 0.14.0-4 builds the plain tag. If wanted later: carry it like
  window-title's `41.patch` (that is upstream PR #41, also still unmerged).
  Network Speed: Plasma's own `org.kde.plasma.systemmonitor.net` - the only
  Plasma-6-native one (every third-party "Plasma 6" netspeed widget checked -
  dfaust, varlesh, PlasmaDrifter, plasma-27, henriquecarmine - shells out to
  /proc/net/dev through the Plasma5Support compat layer) - with our own QML
  sensor face `dev.shani.netspeed` (usr/share/ksysguard/sensorfaces): down
  over up in two half-bar-height lines; the stock faces were a tiny chart or
  ~200 px of labels. Arrows use the scheme's positive/accent colours (fixed
  mint was 1.51:1 on the light panel).
  **Konsole ANSI palettes** were broken: light black = the background
  (1.00:1, invisible), cyan = foreground in both, every intense colour equal
  to its normal one, bold text drawn coral. Now 16 distinct Saturn-toned
  colours, >=4.5:1 on their background (background-mirroring slot: 1.2:1,
  its intense 3:1); `check-contrast.py` now audits Konsole schemes too.
  Terminals are frosted (colorscheme `Opacity=0.9`, `Blur=true`, profile
  `BlurBehind=true`, Yakuake `Translucency=true`).
  **Desktop widgets can't be blurred** by any theme: libplasma requests KWin
  blur only for panel/popup *windows*; widgets live inside the desktop window
  and plasma-desktop's containment has no blur. `build-desktoptheme.py`'s
  `frost()` gives them a frosted look instead (widget background and the
  Utterly-Round clock face at 0.78; opaque/ and solid/ variants untouched). Its sensors come from
  ksystemstats' network plugin, which needs KF6 NetworkManagerQt (pulled in
  by plasma-nm) - without it the widget is blank.
  **Flatpak Qt apps** can't see /usr/share/Kvantum; theme-sync keeps
  ~/.config/Kvantum/Saturn{,Dark} identical to the installed themes
  (sha256-compared; the first-login override grants that dir read-only).
  Keep each side's corner and edge pieces the same thickness (a 24 px edge
  beside a 36 px corner made the top-right corner stick 12 px out).
  **Yakuake:** the Saturn skin never applied - skel put `Skin=` under
  `[Window]`; Yakuake reads it from `[Appearance]` (yakuake.kcfg), and its
  `title.skin` used invented keys (`[CloseButton]`, `[MaximizeButton]`...)
  referencing 15 images that didn't exist. Now `build-yakuake.py` makes
  Saturn/Saturn-Dark skins in Yakuake's real format (3 title buttons + tab
  +/x), colours read from the colour schemes' Header group; theme-sync
  switches the skin with the look; checker rules for both. With
  `Translucency=true`, button images must be opaque (transparent pixels show
  the desktop through - a visible box).
  **GTK apps:** skel shipped stale GTK colour files (`*_saturn` names Breeze
  GTK never reads, old palette) and `gtk-4.0/*.css` symlinks relative to the
  wrong directory, which blocked kde-gtk-config from writing - GTK 4 apps
  stayed stock Breeze blue. kde-gtk-config regenerates them from the scheme
  at every login (`applyAllSettings`), so skel now ships only settings.ini.
  GTK 3/4 theme is `Breeze` in light *and* dark (verified A/B: `Breeze-Dark`
  ignores the generated colours in GTK 4); `Breeze-Dark` only for GTK 2.
  Test trap 3: kded and portals are D-Bus-activated, so the session test
  must `dbus-update-activation-environment --all` like startplasma, or they
  never see kdedefaults (cursor/icons wrong). Login greeter: config paths
  and the Saturn Plasma style verified; wallpaper-behind-greeter needs a real
  Wayland boot (X11 --test mode can't show the layer-shell stacking).
  The Plasma style is now **Utterly-Round** (GPL-2.0+, pinned `7e011c1`,
  assembled by `build-desktoptheme.py`) — complete, rounded, blur-masked,
  follows the Saturn colour schemes; previously 4 hand-generated surfaces,
  everything else stock Breeze. `check-package.py`'s
  `validate_theme_references` cross-checks every theme name in LnF
  defaults/skel/greeter against what's shipped and light/dark consistency.
  **Test-harness traps (both cost a false diagnosis here):** `startplasma`
  (a) prepends `~/.config/kdedefaults` to `XDG_CONFIG_DIRS` — without it the
  shell ignores the applied Global Theme and loads Breeze — and (b) sets
  `XDG_CURRENT_DESKTOP=KDE` — without it Qt skips the Plasma platform theme
  and apps get no colour scheme (Breeze Light views inside a dark Kvantum
  window, which looks exactly like a Kvantum contrast bug; it isn't). The
  session script sets both; don't "fix" theming from a run without them.
  **A harness `PASS` used to mean only "the PNG is non-empty" — fixed
  2026-09-26.** `shot()` is `import -window root`, which captures the whole
  screen whatever is on it, so an app that never opened still produced a
  full-desktop frame and scored `PASS`. That is how a Yakuake shell-resolution
  bug above survived a green run. Screenshot steps now `compare` each shot
  against the `desktop` baseline and report the pixel delta, and a new
  `yakuake shell resolution` line fails on the warning text; the thresholds
  are computed from the image with `identify`, **not** `$W`/`$H` (`H` is never
  set in that scope and `set -u` aborts the run). Yakuake's stderr now goes to
  `$OUT` rather than `/tmp`, so it survives a `--rm` container — the run that
  found the bug wrote it to an unmounted `/tmp` and lost it. When adding a
  screenshot step, assert the subject is *visible*, not merely that a file
  appeared.
  `RESEARCH-FINDINGS.md` predates all of this; its §1 table, §6.8 (Id) and §9
  items are stale.

- **Plasma 6.8 / Union (KDE's 2026-2028 styling goal) — WATCH item, added
  2026-09-26.** KDE's stated goal for this cycle is a new design system
  (Ocean) plus a unified theming engine (Union) that Breeze and Oxygen must
  keep working through, targeted at Plasma 6.8. Nothing in this package or in
  `shani-install-media/image_profiles` references 6.8, Union or Ocean
  (verified by grep). Exposure in descending risk order, as actually built
  here — (1) **Aurorae v2 window decorations** are the most
  framework-coupled piece: Saturn/Saturn-Dark replace Breeze's decoration
  entirely via `library=org.kde.kwin.aurorae.v2` (generated by
  `build-aurorae.py`), so anything that changes how decorations are consumed,
  or an Aurorae v2 API change, hits the 12 px corners and measured shadow
  directly. (2) **The desktop theme is a build-time snapshot of Breeze, not a
  runtime reference** — `build-desktoptheme.py` `copy_tree`s from the
  `plasma-workspace` present in the build environment (`source=()` is empty,
  so there is no pinned Breeze tarball) and replaces Breeze's `plasmarc`
  wholesale, precisely because per-file Breeze fallback would leave the rest
  of the shell stock Breeze. This half is the safer one: new upstream
  surfaces are copied automatically and the build **fails closed** on artwork
  drift — `frost: nothing matched in {rel} - upstream artwork changed?`
  (`build-desktoptheme.py:130`). (3) **Kvantum** tracks Qt styles, not KDE's
  theming engine, so Union is not its axis; the vendored MacTahoe
  `kvantum-upstream/` is what to re-check. (4) **Signal gap:** `pkgver=1.0`
  never moves, so nothing marks a rebuild against a new Plasma — a theme built
  against 6.7 and one built against 6.8 are indistinguishable by version.
  **When 6.8 lands, verify with the existing harness rather than by reading
  configs:** build the package, run `shani-desktop-plasma/tests/plasma-session.sh`
  (real kwin_x11 + plasmashell, Arch container, package at `/pkg`), and check
  window corners + shadow (Aurorae v2), panel/dock present and themed
  (`layout.js` must stay copies, not symlinks — bug 6), splash loads
  (`tests/render-splash.py` — bug 10), Konsole colours (`ColorScheme=` under
  `[Appearance]` — bug 12), and that no surface silently falls back to stock
  Breeze/Next. A `plasmarc` or decoration regression will not fail the build.

  **Pre-6.8 baseline captured 2026-09-26** on `plasma-workspace 6.7.5-1`
  (Arch `extra`, version verified with `pacman -Si`, not assumed), running
  `tests/plasma-session.sh` in an Arch container with the package tree at
  `/pkg`, **all three looks in one container**: 39 `RESULT` lines, **0
  failures**, `HARNESS_EXIT=0` for `Saturn-Dark`, `Saturn` **and**
  `Saturn-Twilight` — screenshots `desktop`, `calendar`, `launcher`,
  `dolphin`, `maximized`, `konsole`, `lockscreen`, `gtk3`, `gtk4`,
  `yakuake`, `kvantum`, plus `yakuake shell resolution` and `plasmashell
  theme warnings`, per look. Those `RESULT` lines are committed verbatim as
  `shani-desktop-plasma/tests/baseline-plasma-6.7.result` and are
  byte-identical to the real run, so a post-6.8 run can be diffed
  mechanically instead of eyeballed; that file also carries the container
  recipe. It is inert in the payload — the `package()` function only copies
  `etc/` and `usr/` into `$pkgdir`, so `tests/` never ships. Diff **only**
  the `RESULT` lines: `DETAIL` lines carry per-shot pixel margins that vary
  run to run and would produce false diffs. Any `RESULT` line that is not
  `PASS`   is the regression. All three `yakuake-*.log` files are 0 bytes,
  confirming the empty-`Command` warning is gone on every look.
  Regenerate with **one** container for all three looks (a ~2.6G install each
  time otherwise) and a **mounted** `out/` dir, or the screenshots and app
  logs are lost with `--rm`. Every app log (`kwin`, `plasmashell`,
  `konsole`, `yakuake`, `lock`) now goes to `$OUT` for that reason — the
  `plasmashell theme warnings` assertion reads one of them, so on an
  unmounted path a FAIL would have been undiagnosable.
  **Two things that look like bugs in a run but are not.** (1) `org.kde.KSplash
  failed: exited with status 1` appears in every container run: the headless
  session has no real splash compositing. The splash itself is fine —
  `tests/render-splash.py` exits 0 for all three looks, and the captured
  stage1/stage5 frames are real renders (mean stddev 24-30, not black), so
  bug 10 has not regressed. (2) `Parent=FALLBACK/` in the profile is
  **correct** and must not be "fixed" to `Built-in/`: konsole renamed only
  the built-in profile's *display name*, deliberately keeping the magic path
  string `FALLBACK/` ("For backward compatibility with existing profiles, it
  should never change", `Profile.cpp` `BUILTIN_MAGIC_PATH`). Konsole's own
  test fixture and an autotest both assert that exact spelling, and a bad
  `Parent=` would fail only to a `qCDebug` line and then silently inherit
  built-in defaults anyway.

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
- **CI status — corrected, was stale.** Three workflows exist:
  `lint.yml`, `security.yml` (checksum scan via `shani-ci-commons`),
  `trigger-build.yml` — this previously said "no CI workflows," which was
  wrong at the time it was checked; verification is pre-commit hooks
  *and* CI, not pre-commit alone. Keyring-checksum coverage now lives in
  `shani-ci-commons`'s `security.yml` (scan-type: checksum); the
  standalone `check-keyring-sync.yml` was pure duplication and has been
  removed (its shellcheck step is absorbed by the shared branch).
- **Stale `.SRCINFO` in 10 of 17 tracked packages — FIXED.** Was: confirmed by actually running `makepkg --printsrcinfo` and diffing against the committed file (real mismatch — `filesystem/.SRCINFO` still described the pre-rebrand "Base Arch Linux files" while `PKGBUILD` was "Base Shani OS files", plus `foo2zjs-nightly`, `game-devices-udev`, `gnome-shell-extension-gsconnect`, `hplip-minimal`, `lsb-release`, `plasma-setup-git`, `shim-signed`, `snapd`, `waydroid-helper`). All 10 regenerated via a real `makepkg --printsrcinfo` run in the builder container (`--user builduser`, a writable scratch copy to work around real-Docker's lack of `--userns=keep-id`) and committed.
- **19 of 41 PKGBUILDs have no `url=` — FIXED.** Was: confirmed by grep and independently by `namcap` ("E/W: Missing url") on `shani-core`/`shani-network`. All 19 (`desktop-entry-hider`, `shani-accessibility`, `shani-bluetooth`, `shani-core`, `shani-desktop-cosmic`, `shani-desktop-gnome`, `shani-desktop-plasma`, `shani-fonts`, `shani-multimedia`, `shani-network`, `shani-peripherals`, `shani-printer`, `shani-scanner`, `shani-storage`, `shani-tools-extra`, `shani-tools-network`, `shani-tools`, `shani-video-guest`, `shani-video`) now have `url="https://github.com/shani8dev/shani-pkgbuilds/tree/main/<pkgname>"` (they're first-party metapackages with no separate upstream repo, so their own subdirectory in this repo is the correct URL — matching the convention `os-installer-config` already used), `pkgrel` bumped on each.
- **3 PKGBUILDs have no `# Maintainer:` line — FIXED.** Was: `desktop-entry-hider/PKGBUILD:1`, `plasma-setup-git/PKGBUILD:1`, `shani-deploy/PKGBUILD:1` (namcap-confirmed on the last). All 3 now have the standard `# Maintainer:` line, `pkgrel` bumped.

- **`os-installer-config` arch mismatch — FIXED.** Was `arch=('x86_64')` with no compiled output (`namcap`: "W: No ELF files and not an 'any' package"); now `arch=('any')`.
- **`os-installer-config` undeclared script runtime deps — FIXED.** `depends=('bash' 'python' 'python-yaml')` added (needed by `etc/os-installer/po/config_to_pot.py` and the shell scripts under `etc/os-installer/scripts/`).
- **os-installer-git missing `git` makedepends — FIXED.** `makedepends` now includes `git`, matching the `git+` `source=`.
- **Non-SPDX `license=()` identifiers across 27 PKGBUILDs — FIXED.** Was: `namcap` flags this at ERROR level (confirmed on `os-installer-config`: "E: BSD is not a valid SPDX license identifier"). Each of the 27 was researched individually (not blanket-substituted) to find the package's *actual* license, not just reformat the legacy shorthand: `os-installer-config` → `BSD-3-Clause` (verified — this repo's own local `LICENSE` file is BSD-3-Clause, contradicting the PKGBUILD's bare `'BSD'`); `lsb-release` → `GPL-2.0-or-later` (Arch's own official `extra` package DB already uses this exact identifier for the same package); `plasma6-applets-window-title` → `GPL-2.0-only` (upstream's real LICENSE file is plain GPLv2 with no explicit "-or-later" declaration found anywhere); `systemd-oomd-defaults` → `LGPL-2.1-or-later` (systemd's own README states this exact identifier for all its code); `os-installer`/`os-installer-git` → `GPL-3.0-or-later` (GNOME upstream's `meson.build` explicitly declares `license: 'GPL-3.0-or-later'`); `snapd` → `GPL-3.0-only` (confirmed via an actual per-file copyright header in snapd's own source — "under the terms of the GNU General Public License version 3", no "or later" clause — not just the ambiguous generic COPYING boilerplate, which contains that phrase regardless of the project's real choice); `shani-deploy` and the 19 `shani-*` meta-packages → `GPL-3.0-only` (first-party, matches this repo's own top-level `LICENSE` and no explicit "-or-later" declaration exists anywhere in the ecosystem). `.SRCINFO` regenerated for the 3 affected packages that track one (`lsb-release`, `plasma6-applets-window-title`, `snapd` — diffed against the pre-change file each time to confirm the license line was the *only* change) via a real `makepkg --printsrcinfo` run in the builder container.
- **game-devices-udev lost GPG tag verification — FIXED, non-obviously.** Was: `source=("git+${url}.git#tag=$pkgver" ...)` had been changed to `#commit=<40-hex-sha>` in an earlier fix for a *different* real problem (a `#tag=` reference can be force-moved upstream without this PKGBUILD ever changing — `check-skip-checksums.sh` correctly flags this), but that fix accidentally dropped `validpgpkeys` and the `?signed` URL suffix entirely, leaving zero cryptographic verification. The two fixes looked mutually exclusive (makepkg's git-source PGP verification is normally tied to `#tag=`, not `#commit=`) — but verified live, `?signed` **does** work with a `#commit=<sha>` fragment too: `source=("git+${url}.git?signed#commit=$_commit" ...)` plus `validpgpkeys=('6E58E886A8E07538A2485FAED6A4F386B4881229')` gets both properties at once (immutable commit pin *and* real GPG verification), confirmed via an actual `makepkg --nobuild --nodeps` run in the builder container: "Verifying source file signatures with gpg... game-devices-udev git repo ... Passed (WARNING: the key has expired.)". The key genuinely is expired (`git verify-tag`/`git verify-commit` against the real upstream repo both return "Good signature ... [expired]", not a wrong/forged key — almost certainly why this toggled back and forth across many prior commits) — but makepkg treats an expired key as a warning, not a hard failure, so this is still strictly better than the unverified SKIP state it replaces. Also ran a full real `makepkg -f --nodeps` (not just `--nobuild`) to confirm the package actually still builds end-to-end with this source form; re-ran `check-skip-checksums.sh --all` afterward to confirm nothing else regressed.

- **The `trailing-whitespace` pre-commit hook corrupts `.patch` files — FIXED (root cause of the escpr2 "Hunk #3 FAILED" mystery).** In a unified diff, a context line is `<SPACE>content`; a whitespace-only context line is *exactly one space*. The hook trims it as "trailing whitespace", turning the line into an empty string — which `patch` then rejects, breaking hunk parsing (the escpr2 `prepare()` failure was "Hunk #3 FAILED at 459", and its vendored `bug_x86_64.patch` is whitespace-sensitive: sha256 `57c7a32b…` applies cleanly, the trimmed variant `f68afef0…` doesn't). Proven: the successful full build at 11:52:27 used the good file (`Hunk #3 succeeded at 462 (offset 3 lines)`), then a `pre-commit run --all-files` at 11:52:55 silently re-trimmed it. Fix: `.pre-commit-config.yaml` now has `exclude: '\.patch$'` on that hook. A later ecosystem-wide whitespace-cleanup pass (2026-09-18) hit exactly this trap independently — live-tested 2 of these same `.patch` files against their real upstream tarballs and confirmed a whitespace-stripped version actually fails to apply — and correctly excluded/reverted all `.patch` files from that commit rather than assume the class was safe. `git diff --ignore-all-space -- '*.patch'` is currently clean (no drift) — the "suspect" files noted here at the time of this entry have since been resolved back to their correct content; re-check with that same command before trusting this note if it's been a while.
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
- **`shani-peripherals` declared `pam-u2f` and `pam-krb5` with neither
  referenced by any PAM stack — two inert dependencies, found 2026-09-26 by
  auditing every module the peripherals set ships. `pam-u2f` is now FIXED;
  `pam-krb5` is still open.** Same class as the `libpwquality` entry below,
  and found the same way: the module is installed, so it looks supported, but
  nothing loads it. Verified by installing `gdm`, `plasma-login-manager`,
  `sddm` and `kscreenlocker` together and grepping **every** file in
  `/etc/pam.d` and `/usr/lib/pam.d`: `pam_u2f` and `pam_krb5` appeared in
  **zero** stacks, while `pam_fprintd` appeared in exactly two
  (`gdm-fingerprint`, `kde-fingerprint`) and `pam_pkcs11` in two
  (`gdm-smartcard`, `kde-smartcard`). The asymmetry that makes this easy to
  miss: smartcards and fingerprints look supported for the same reason and
  genuinely are, because `gdm`/`kscreenlocker` ship PAM services referencing
  them; u2f and krb5 had no such service and nothing in the tree provided one.
  **`pam-u2f` — FIXED (2026-09-26).** `shani-settings` now ships
  `etc/pam.d/system-auth` with `auth sufficient pam_u2f.so`, so a FIDO2/U2F
  key works at any graphical login and for `sudo` with no hand-editing. Two
  things that are easy to get wrong and were both measured rather than
  assumed:
  (a) `system-auth` is the right file, and `system-local-login` is the
  tempting wrong answer — `plasmalogin` (the Plasma edition's actual login
  manager) includes `system-login`, *not* `system-local-login`; the two are
  siblings that both include `system-auth`, so `system-auth` is the only
  chokepoint reaching GNOME, KDE, Plasma and getty together.
  (b) `sufficient`, never `required`: with no key present `pam_u2f.so` returns
  `PAM_AUTHINFO_UNAVAIL` (9), which under `required` fails the whole stack and
  would stop the *password* working on any machine without a key. Verified
  with a compiled libpam client feeding a password through the conversation
  callback, called as a **non-root** user through a service that really
  includes the file — correct password succeeds, wrong password still rejected,
  `pam_permit`=0 / `pam_deny`=7 controls in the same run. **Harness trap:** an
  earlier attempt looked like an auth bypass purely because it ran as root
  (where `pam_rootok.so` short-circuits the stack) and tested
  `/etc/pam.d/su`, whose `auth` stack never includes `system-auth`. Do not
  reuse that shape.
  Note `pam-u2f` is deliberately **not** a dependency of `shani-settings` (it
  ships in `shani-peripherals`); if genuinely absent PAM skips the module and
  the `sufficient` line falls through to the password, so the failure direction
  is safe. Also note `shani-settings` `pkgrel` must be bumped whenever
  `shani-peripherals` gains a PAM-referenced module, since the two ship
  independently.
  **`pam-krb5` — still open.** No stack references it; Kerberos cannot
  authenticate. Wiring it is not a one-liner the way u2f was: it needs a realm
  and a keytab, so it is a deployment decision rather than a missing line.
  `shani-docs`' `security/hardware-auth.md` now says a FIDO2 key can log in
  and calls Kerberos out separately as unwired.
  Everything else in that package checks out and is genuinely wired: all nine
  units `shani-peripherals.install` enables exist (`fprintd`, `bolt`,
  `ratbagd`, `geoclue`, `upower`, `usbmuxd`, plus the `pcscd`/`lircd`/`gpsd`
  sockets — an earlier "no unit file" reading of this was a container artifact
  of a partially failed install, not a gap), `libfprint` ships
  `70-libfprint-2.rules` for SPI sensors, and `android-udev` ships
  `51-android.rules`. `game-devices-udev` ships `uinput.conf` rather than a
  `.rules` file, so a "no udev rules" grep reports it as missing when it is
  not. `apcupsd` and `inputattach` are commented out in that `.install`.

- **`shani-core` declares `libpwquality` but nothing ever loads it — inert
  dependency, NOT fixed because it needs a policy decision.** The inverse of
  the `gvfs-google` case above: that entry named a package that does not
  exist, this one names a package that exists and is never used.
  `shani-core/PKGBUILD:30` declares `libpwquality`, but no PAM stack anywhere
  in the overlay references `pam_pwquality` (checked across `shani-settings`,
  `shani-install-media`, `os-installer-config` and this repo, excluding
  caches), and neither `shani-settings` nor `os-installer-config` ships an
  `/etc/pam.d` at all. Net effect: **no password strength policy is enforced
  on a Shanios install** — the library is installed and inert. Either wire
  `pam_pwquality.so` into the `password` stack (note that a missing module
  fails silently rather than erroring, so it needs a deliberate test) or drop
  the dependency; do not leave it looking enforced. **Its control-flag
  behaviour is now measured** (2026-09-26, compiled libpam client, no sensor
  attached): the line must go in as `password sufficient`, not `required` —
  `pam_pwquality.so` returns `PAM_AUTHINFO_UNAVAIL` (9) when the password is
  merely too short, and under `required` that fails the stack and so would
  lock the user out of changing their password at all, while under
  `sufficient` it is ignored and the change proceeds. The
  `retry=3 minlen=12` form was verified end to end: a 5-character password is
  rejected, a valid one is accepted, and `su`, `passwd` and `chpasswd` all
  still work with the line in place (`chpasswd` matters — the installer sets
  the first password through it, and an early "failure" there turned out to be
  a test artifact, reproduced unmodified and modified to prove it). Password
  *expiry* is a separate axis and is deliberate: shadow defaults apply, so
  `max-days` is `99999` and `inactive-days` is `-1`, matching the server
  profile's `/etc/default/useradd` (`EXPIRE=` empty, `INACTIVE=-1`). That
  matches NIST SP 800-63B, which advises against periodic forced rotation
  absent evidence of compromise. `shani-docs` now documents the real default
  (`system/users-groups.md`, commit `7112701`).
- **Fingerprint login: which editions can actually use a finger — audited
  2026-09-26, and the answer is narrower than the docs claimed.** The rule
  that makes this non-obvious: **the PAM service that makes an enrolled
  finger usable ships with the login manager, not with `fprintd`.** So
  grepping the overlay for `pam_fprintd` finds nothing and looks like the
  `libpwquality` bug, when the real answer lives in the display-manager
  packages. `gdm` ships `/etc/pam.d/gdm-fingerprint` (works at the GNOME
  login screen) and `kscreenlocker` ships `/usr/lib/pam.d/kde-fingerprint`
  (KDE lock screen, and only once `Authenticators/Fingerprint` is enabled in
  `kscreenlockerrc` — it is off by default). **Shanios Plasma does not use
  SDDM**: it ships `plasma-login-manager` and logs in via `/usr/bin/plasmalogin`
  (`shani-desktop-plasma` depends on it; `os-installer-config`'s
  `configure.sh` adds a `plasmalogin` autologin branch ahead of the sddm one
  and comments "the plasma image has no sddm"). Its PAM services
  (`plasmalogin`, `plasmalogin-autologin`, `plasmalogin-greeter`) contain no
  `pam_fprintd`, and neither do `system-login` or `system-auth`, so **no
  edition but GNOME can use a finger at the login screen**. `cosmic-greeter`
  ships no PAM service at all. `greetd` (`/etc/pam.d/greetd`, used by the ISO
  profile) includes `system-local-login` and likewise has no `pam_fprintd`.
  `libpam` searches both `/etc/pam.d` and `/usr/lib/pam.d` (confirmed in its
  compiled-in strings), which is why a service inside a package payload works
  with no `/etc` file at all. **A leading `-` in a PAM line is not a
  comment**: `kscreenlocker`'s `kde-fingerprint` contains
  `-auth required pam_fprintd.so`, and a compiled libpam client showed that
  line behaving *identically* to the unprefixed one — it is live, not
  disabled.
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

- **shani-settings pkgrel never reset after a pkgver bump (Med).** `shani-settings/PKGBUILD:4-5` (currently `pkgver=0.0.5`, `pkgrel=41`) — confirmed via `git log -p`: commit `40152de` (2025-02-09) bumped `pkgver` 0.0.4→0.0.5 while leaving `pkgrel` at 2 instead of resetting to 1; it has climbed to 41 since, still under the same `pkgver=0.0.5`, without ever resetting.
- **`brlaser-debug`/`splix-debug` broken build-id symlink (Low).** Confirmed by actually building both packages and running `namcap` on the result: "E: Symlink (usr/lib/debug/.build-id/...) points to non-existing ../../../cups/filter/rastertobrlaser" (and the same for splix's `rastertoqpdl`/`pstoqpdl`). makepkg's auto-generated `-debug` split package computes the build-id symlink relative path assuming a standard `/usr/bin`-style install location; it breaks for a CUPS filter binary under `/usr/lib/cups/filter/`. Likely affects any other CUPS-filter package here that produces a `-debug` split (e.g. `cnijfilter2`, `hplip-minimal`, `foo2zjs-nightly`) — not individually re-verified. Cosmetic (only affects the optional debug package), not the main package.

- **GNOME gschema override had 30 dead keys; COSMIC theme Builder accent was
  black — FIXED (2026-09-24).** `shani-desktop-gnome`'s
  `99_shanios-gnome.gschema.override` set keys for schemas the GNOME edition
  doesn't have, and `glib-compile-schemas --strict` passes regardless (it
  ignores them silently): gnome-terminal and gedit (not installed), Text Editor
  (a Flatpak — can't see host overrides), File Roller (not shipped),
  `org.gnome.nautilus.desktop` (removed in Nautilus 3.28), and the file-chooser
  keys under a wrong-case `org.gtk.settings.file-chooser`. Found by resolving
  every key with `gsettings list-keys` against GNOME 50's real schemas; now
  92/92 keys live, file-chooser applied to both `org.gtk.Settings.FileChooser`
  (GTK3) and `org.gtk.gtk4.Settings.FileChooser`. The same check runs in a
  real image as `shani-testbed`'s `slot-test <slot> fresh-user`
  (`gschema-override-keys-live`). `shani-desktop-cosmic`'s theme is now
  generated, complete and Saturn — `build-theme.rs` (not shipped; header has
  the exact libcosmic revision and command) builds Dark/Light + their
  Builders with COSMIC's own `ThemeBuilder` and writes them through
  cosmic-config as cosmic-settings does. Found on the way, all verified with
  COSMIC's own loader (`Theme::get_entry`): the theme config is **v2** in
  COSMIC 1.8 while the skel shipped **v1** (read only through cosmic-config's
  `version - 1` fallback); the v1 Builder accent was `Some(black)` (the first
  appearance change in Settings rebuilt the theme with a black accent); the
  v1 Light theme had 15 of its 29 keys, so the rest came from the *dark*
  default — it loaded as `name=cosmic-dark, is_dark=true`. Now: 0 load errors,
  dark accent `#ff7f50` on `#252434`/`#2d2c3b`/`#353443`, light accent
  `#bc3e18` on `#f2eee9`, frosted panel/applets/system UI. GTK: the
  generated `gtk-4.0/cosmic/{dark,light}.css` ship with **relative**
  `gtk-{3,4}.0/gtk.css` links (libcosmic's `apply_gtk()` makes absolute ones
  into the generating user's home) and `CosmicTk.apply_theme_global=true`,
  so libadwaita apps get Saturn from first login (rendered: adwaita-1-demo
  indigo vs stock grey); plain-GTK4 apps don't use those named colours
  (upstream behaviour). COSMIC Terminal: `Saturn Dark`/`Saturn` colour
  schemes generated from the shipped Konsole schemes (same 16 colours +
  fg/bg/cursor), FiraMono Nerd Font, login shell (`command: ""`, upstream's
  default; was `/usr/bin/fish`), stale `hold:` key removed — all parsed with
  cosmic-term 1.8.0's serde semantics.

- **Plasma look-and-feel previews had the wrong names; theme sync ran only at
  login — FIXED (2026-09-24).** Per plasma-workspace 6.7.5
  `shell/packageplugins/lookandfeel/lookandfeel.cpp` the files are
  `previews/preview.png`, `previews/fullscreenpreview.jpg` (the `.png` all
  three looks shipped is never found), `previews/splash.png` (Splash Screen
  KCM) and `previews/lockscreen.png`. Now: fullscreen previews re-encoded as
  JPEG; splash previews rendered from each look's real `Splash.qml`
  (`tests/render-splash.py`); lock-screen previews from the real
  `kscreenlocker_greet --testing` capture (`tests/plasma-session.sh`), with
  the desktop panel the windowed greeter leaves visible (rows 0-31) cropped
  off. `check-package.py` enforces these names and rejects a
  `fullscreenpreview.png`. `shani-theme-sync.sh --watch` (the autostart
  `Exec`) syncs once, then re-syncs on the session bus's KConfig
  `ConfigChanged` for `/kdeglobals` and `KGlobalSettings.notifyChange`, so
  Kvantum/GTK/Konsole/Yakuake follow automatic light/dark switching and the
  Colors KCM mid-session instead of at the next login. Verified in a real
  D-Bus session: a notify write and `plasma-apply-colorscheme` both switched
  all four; with the watcher stopped (negative control) none did.

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
