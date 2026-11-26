# shani-pkgbuilds: its part of the shared architecture

The plan for all repos is `../shani-shell/docs/SHARED-ARCHITECTURE.md` (https://github.com/shani8dev/shani-shell/blob/master/docs/SHARED-ARCHITECTURE.md). Read it first; its rules apply
here. This file is only this repo's part; change the plan there, not here.

**Role:** packaging: carries out the splits when each phase lands.

**Do as much of this as your task allows** (never breaking a consumer), and
add a line to the plan's Status section when you finish something:

- Phase 2: the shared backends repo (name not decided yet; split PKGBUILD per domain); `shani-link` depends on its phone package.
- Phase 4: `shani-backup` + `shani-backup-gtk`. Phase 5: `shani-chronoa` (no GTK) + `shani-chronoa-gtk`; Chronoa's `shani-link` dependency becomes optional.
- Until then: keep `check-deps` honest and pin consumers to merged commits only.
