# Tidybar

**Tidybar is a personal fork of [Thaw](https://github.com/thaw-app/Thaw)** (itself a fork of Ice by Jordan Baird), a menu bar
manager for macOS. Forked from Thaw **2.0.1** on **2026-09-07** by Yoav Sror.

## Modifications

This is a modified version of Thaw. Per GPLv3 section 5(a), the modifications are:

- **2026-09-07 -- Phase 0 (identity):** renamed to Tidybar; bundle identifier `com.yoavsror.tidybar`;
  URL scheme `tidybar://`; version restarted at 1.0.0; Sparkle update feed removed (this build never
  self-updates); repository and donation links point at this fork. No behaviour changes.

- **2026-09-07 -- Phase 1 (behaviour):** new icons land Visible; one configuration for every display (no
  per-display settings, no global template); the overflow panel is the Tray; Sparkle removed entirely.
  Version 1.1.0.

Subsequent changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Why a fork

Two sections (Visible / Hidden) instead of three, every new icon lands *visible* by default, one
configuration for all displays, and no automatic updates. A menu bar manager should stay static.

## Building

Requires Xcode 26 on macOS 26. Ad-hoc signed; Accessibility must be granted once after install.

    xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Release build

(The Xcode project, scheme and source folders keep their upstream names on purpose so that
cherry-picking from upstream stays cheap. The *product* is `Tidybar.app`.)

## Upstream

Thaw: https://github.com/thaw-app/Thaw -- reviewed periodically; changes are cherry-picked deliberately, never pulled wholesale.
The upstream README as of the fork point is preserved at [docs/UPSTREAM-README.md](docs/UPSTREAM-README.md).

## License

GNU General Public License v3.0 -- see [LICENSE](LICENSE). Copyright (Ice) 2023-2025 Jordan Baird;
Copyright (Thaw) 2026 Toni Foerster; Copyright (Tidybar modifications) 2026 Yoav Sror.
Original copyright notices in source files are preserved unchanged.
