# Changelog

## 1.1.1 — 2026-08-30

### Product changes

- Fixed the memorable `bash <(curl -fsSL https://bureau.regionallyfamous.com/install)` command so Omarchy's intentional initial disabled-plugin state is followed immediately by theme, font, branding, and plugin activation in the same run.
- Added a bounded catalog-discovery wait so setup does not race Omarchy's asynchronous plugin rescan after a fresh validated checkout.
- Made a rerun recover an existing validated but disabled One-Bit Bureau checkout without requiring manual cleanup or a second install command.
- Clarified that executing the quick bootstrap is activation consent; the inspect-first and manual paths remain available for users who want to review the source before running it.

### Release verification

- Replaced the public-lifecycle shortcut with the literal hosted command running inside a real pseudo-terminal, so a release cannot pass by invoking setup separately with `--yes`, and added a delayed-catalog regression for the handoff race.

## 1.1.0 — 2026-08-30

### Product changes

- Added one shared Bureau Inspector for desktop objects, dock applications, and overview windows, with stable Identity, Facts, and Actions regions, visible unavailable-action reasons, local-only icon loading, keyboard access, accessibility metadata, and reduced-motion behavior.
- Added bounded 64-item desktop multi-selection, named `noun -> verb -> destination` routing slips, real folder and Trash destinations, external local-file drops, operation receipts, Escape cancellation, and narrowly provable Undo for unchanged regular-file moves.
- Added a hardened local transaction helper with bounded JSON receipts, private atomic journals, collision-free destinations, cross-filesystem rollback, partial-batch reporting, launcher trust demotion, hash-proven Undo, and parent-death containment for the `gio trash` child.
- Added a truthful per-app Window Ledger with 1/2/3+ marks, active and cross-workspace state, deterministic most-recently-used focus, explicit Activate and Close actions, and no duplicate launch when compositor state is stale.
- Added the overview workspace board with stable ordinary-workspace ordering, occupancy, keyboard and context parity, validated window moves, and an overview that remains open after routing.
- Expanded the original offline icon system to 32 authored roles covering all 36 launcher-visible applications in a fresh Omarchy Quattro install, with a one-bit Application fallback for unresolved icons and a grayscale-native fallback that keeps uncommon applications recognizable without breaking the composition.
- Hardened compositor identity reconciliation so every live Wayland window maps to at most one Hyprland ledger record, generated Chromium identities group correctly, stale compositor remnants cannot create ghost dock entries, and real multi-window applications retain truthful counts across workspaces.
- Added an end-user-focused README, detailed technical wiki, and a deliberately staged real-application gallery using local offline content, a grayscale Files study, five matching dock marks, and acceptance assertions that reject first-run windows or other visual debris.
- Corrected Dock **Get Info** so it opens the shared Inspector while **Manage Icons** remains a distinct command.
- Preserved one deliberate Wayland limit: internal desktop drags do not pretend to cross into the separate dock layer-shell window. Native external file drops and every proven in-surface route remain supported.

### Release verification

- Expanded the local gate to 64 desktop Python tests, 69 dock and Window Ledger tests, 10 Inspector tests, 9 overview and workspace tests, shared-host source contracts, strict theme rendering, icon-catalog coverage, and controller-death containment checks.
- Expanded the disposable x86_64 graphical suite with Inspector, multi-route/receipt/Undo, Window Ledger, workspace movement, unmatched-icon fallback, exact public lifecycle, and a debris-intolerant 45-frame review gallery.

## 1.0.2 — 2026-08-30

### Product changes

- Added the memorable first-party installer at `https://bureau.regionallyfamous.com/install`, backed by a tiny public Cloudflare Worker with no data bindings, cookies, third-party page assets, or mystery redirect service.
- Kept Omarchy’s canonical Git validation and One-Bit Bureau’s explicit unsandboxed-plugin confirmation in the quick path, with the complete audit-first Git commands still documented beside it.
- Added safe already-installed handling, canonical source and release shortcuts, a script-free retro landing page, strict response security headers, and sampled operational observability.

### Release verification

- Added Worker type, route, method, redirect, response-header, exact-installer-byte, shell-syntax, and mocked Omarchy lifecycle tests.
- Passed the complete plugin/theme static gate after the installer additions and verified the production Custom Domain, certificate, canonical redirects, error methods, and byte-identical live shell payload.

## 1.0.1 — 2026-08-30

### Product changes

- Render safe local photograph previews in grayscale on the desktop while preserving the original file bytes and full-color opened view.
- Render unmatched automatic native app icons in grayscale across the dock, drag ghost, preview fallback, app switcher, and icon manager.
- Keep authored One-Bit roles, manual pack assignments, and custom icon files unchanged; explicit Native mode restores the application's original color icon.
- Widen the invisible auto-hide reveal edge to six logical pixels and verify pointer engagement before reveal, improving reliability on scaled and synthetic pointer paths.

### Release verification

- Added deterministic presentation-mode contracts and disposable-guest pixel checks for grayscale Automatic fallbacks, full-color Native opt-out, and byte-identical photo sources.

## 1.0.0 — 2026-08-30

### Product changes

- Established the complete `io.github.regionallyfamous.one-bit-bureau` identity across runtime targets, theme ownership, commands, user state, branding, and public documentation.
- Added the original Bitmap Workbench wallpaper, expressive raster desktop objects, original branding, a branded unlock mark with a 1920×1080 preview, and twelve offline app-role icons.
- Restored real, unmodified desktop thumbnails for bounded local PNG, JPEG, WebP, and BMP files. Selection changes the enclosure and name rail without recoloring the photograph; unsupported or unsafe image inputs use the authored one-bit picture fallback.
- Seeded new docks with Files, Chromium, and Foot, normalized all twelve bundled app-role icons to their painted alpha bounds, and centered them optically inside balanced 48px dock boxes.
- Added automatic Linux app association, manual pack selection, a native-icon opt-out, and a deterministic local icon manager with no external artwork service.
- Added real desktop files, a bottom dock, a searchable window overview, active-application context, safe object-first launcher handling, and pass-through behavior for Omarchy's native `Super` navigation chords.
- Added no-follow, size-capped, record-capped state loading and bounded helper lifetimes; no external icon search, fallback screenshot process, or ImageMagick job runs in the shell.
- Bundled Monaspace Krypton NF 1.400 and Departure Mono 1.500 with upstream licenses and checksums. Setup registers them without changing the selected Omarchy font.
- Added original About and screensaver branding with ownership-aware restoration, plus a Git-native `one-bit-bureau` coordinator, capability-matched theme ownership, commit-aligned updates, and ownership-aware removal.
- Added `one-bit-bureau motion reduce|full|status` around the native inline `reducedMotion` setting so One-Bit Bureau surfaces can remove nonessential transitions without adding a parallel preference store.

### Release verification

- Implemented keyboard navigation, visible focus, assistive-technology labels, practical hit targets, and reduced-motion behavior across the desktop, dock, overview, settings, and icon manager; the disposable runtime pass remains the release gate.
- Passed the disposable x86_64 Omarchy guest test for the exact public Git install, adopt, activate, update, and removal path, alongside desktop, dock, overview, keyboard, notification, lock, opacity, accessibility, and helper-containment checks.
