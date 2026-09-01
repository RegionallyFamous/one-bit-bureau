# Release checklist

## Automated gate

- Run `bash tests/static.sh` from the repository root.
- Confirm `omarchy plugin validate .` passes on the target Omarchy release.
- Confirm the `one-bit-bureau` theme passes strict validation and a real template render.
- Confirm the branded `unlock.png` has transparency and `preview-unlock.png` is 1920×1080 and matches the current mark.
- Confirm all 32 rendered app icons match `pack.json`, all 36 fresh-install application associations resolve to a declared role, the authored Application fallback ships, the font family names and checksums match `fonts/README.md`, and both license texts ship.
- Confirm the desktop policy exposes only regular local PNG, JPEG, WebP, and BMP files at or below 32 MiB as previews; SVG, GIF, oversized, remote, inline, missing, and disallowed-path inputs must fall back without being decoded by the shell.
- Confirm the repository contains no symlinks or executable files; this is required because the same repository is also an Omarchy theme source.
- Run the desktop transaction-helper tests and verify local-path/type/count/byte limits, collision-free copy and move, partial receipts, private atomic journals, child timeout/parent-death containment, launcher demotion, changed-destination rejection, and exact hash-proven Undo.
- Run the Inspector, Window Ledger, and workspace-model suites through `tests/static.sh`; confirm `Experience.qml` owns exactly one Inspector and routes desktop, app, and window actions back to their live owner for re-resolution.
- Run `npm --prefix shortlink ci`, `npm --prefix shortlink test`, remove the generated `shortlink/node_modules`, and then run the repository static gate. Confirm the Worker typecheck, routes, methods, redirects, retired bootstrap endpoints, verified-release installer behavior, and plugin/theme source-safety checks all pass.
- Verify the live landing page displays the same immutable-release and SHA-256 verification sequence as the README. Confirm `https://bureau.regionallyfamous.com/install` and `/i` return `410 Gone`, then verify canonical source/release redirects, 404/405 behavior, HTTPS certificate, and response security headers.
- Build the tagged artifact with `bash scripts/build-release-artifact vX.Y.Z`, publish it only after GitHub release immutability is enabled, and verify that the release API reports `immutable: true` plus the same SHA-256 digest as the downloaded archive. Run `gh release verify` and `gh release verify-asset` when authenticated to inspect GitHub's release attestation.
- Review every bundled upstream diff and refresh `THIRD_PARTY_NOTICES.md` when importing updates.

## Exact public lifecycle in a disposable Omarchy guest

- Start from a clean guest and record the active theme, bar position/transparency, presence and SHA-256 hashes of `~/.config/omarchy/branding/about.txt` and `screensaver.txt`, selected Omarchy font, and whether the One-Bit Bureau command, plugin, theme, source, ownership record, and font directory already exist.
- Run the exact README install block from a clean guest. Confirm it rejects a mutable release record or changed archive digest before Omarchy state changes, stages the commit recorded in the verified release metadata, and contains the exact acceptance test under execution. Repeat from an exact disabled checkout left by an interrupted attempt and confirm the installer adopts it without fetching mutable branch content.
- Confirm the plugin is enabled, the owned `one-bit-bureau` theme is active in `plugin-link` mode, the theme and plugin resolve to the immutable release commit, the top opaque bar and One-Bit Bureau branding are active, both font families are visible to fontconfig, and the previously selected Omarchy font remains selected.
- Run `one-bit-bureau status`, then `one-bit-bureau update --yes`. Confirm the plugin checkout, recorded plugin commit, owned theme installation, and recorded theme commit resolve to the same final release commit; an already active One-Bit Bureau theme must remain active.
- Run `one-bit-bureau remove`. Confirm the plugin payload, owned theme link and any source child, unmodified bundled font directory, unmodified command, and ownership record are gone; the recorded theme, bar settings, and exact prior branding bytes are restored; the selected font is unchanged; and the documented Desktop files, pins, icon choices, custom icons, and positions remain as user data.
- Repeat the branding removal check after editing one installed branding file. Removal must preserve that later edit and retain its corresponding backup rather than overwriting it.

## Disposable Omarchy runtime behavior

- Verify the desktop service with an empty folder, many files, a long filename, a trusted launcher, an untrusted launcher, Trash, and drag/drop. Verify two displays when the release guest exposes two real outputs; otherwise record the unavailable capability without simulating hotplug.
- Verify one click selects, a second click does not accidentally open, double-click and Return open, and clicking empty ground clears selection.
- Verify Control/Shift multi-selection, group dragging, exact route slips, folder and Trash destinations, invalid-target reasons, Escape cancellation, partial/error receipts, Control+Z, and Undo refusal after destination mutation or source collision.
- Open the shared Inspector from a desktop object, dock app, and overview window. Verify stable Identity/Facts/Actions regions, visible disabled reasons, stale/missing targets, destructive confirmation, focus restoration, Escape, accessibility, and reduced motion.
- Verify safe local photographs render as stable grayscale desktop thumbnails; selecting one changes only its enclosing rule and name rail, the source file remains byte-identical, and opening it shows the original color image. Verify unsupported and unsafe images use the authored one-bit picture fallback, which reverses with its name rail.
- Verify untrusted launchers default to Cancel, and both Enter and Escape cancel without executing the launcher.
- Verify the clean first-run dock seeds Files, Chromium, and Foot; all three use their One-Bit Bureau associations, painted-alpha crops, 48px boxes, and a shared optical center without clipping or crowding.
- Verify dock launch, focus-existing-window, pin/unpin, reorder, auto-hide, previews, icon management, and the opt-in app-switcher binding in floating and tiled layouts.
- Open two windows under one app identity across two workspaces. Verify 1/2/3+ marks, active and workspace-split text, most-recent-window focus, the titled Window Ledger, explicit Activate/Close, stale-address fallback, and no accidental duplicate launch.
- Verify all 36 fresh-install app-icon associations resolve to their cataloged authored roles in the dock, drag ghost, preview fallback, app switcher, and icon manager. Add an uncommon app with a resolvable native icon and confirm its automatic fallback is grayscale on every surface; add an app with an unresolvable native icon and confirm the authored Application mark appears instead of a blank. Then confirm explicit Native mode restores the original color and custom files plus manual pack choices render as supplied, all without network access.
- Verify dock and desktop menus preserve their row order while unavailable commands remain visible and dimmed.
- Verify overview hot corner, summon/hide IPC, keyboard navigation, search, preview, close-window action, and workspace changes. Verify output ownership on every real display the release guest exposes.
- Verify the overview workspace rail's stable ordinary-workspace ordering, occupancy, Control+Left/Right selection, Control+Enter scope, Control+Shift+Enter move, context parity, stale destination error, and that the overview remains open while the card re-homes.
- Verify overview selection inverts only the ownership rail, the preview body remains stable, and the active window retains its separate double-rule marker.
- Verify active-app title truncation, an iconless app, an application with a changing title, vertical bar layout, and settings persistence.
- Verify stock Quick Look, Apps search, clipboard, emoji menu, notifications, OSD, lock preview, safe polkit idle/cancel, and theme switching still work. Failed lock or polkit authentication belongs to Omarchy's host-global auth suite because it mutates PAM state and can strand the disposable plugin guest.
- Disable One-Bit Bureau and confirm the stock bar and shell remain usable without restarting the machine; normal Alt+Tab must remain functional.
- With a desktop object, overview, and optional app-switcher focused in turn, verify native `Super + Arrow`, `Super + Tab`, `Super + Shift + Tab`, `Super + G`, `Super + O`, `Super + L`, and `Super + Grave` behavior still reaches Omarchy.
- Verify About/screensaver branding, both bundled fonts in `omarchy font list`, the unlock picker preview, and exact restoration of pre-install branding after removal.
- Drive the dock menu and icon manager without a pointer. Verify logical Tab/Shift+Tab and arrow traversal, Enter/Space activation, Escape dismissal, visible focus on every actionable control, readable assistive-technology names/roles, and practical pointer targets that do not visually inflate the compact controls.
- Run `one-bit-bureau motion reduce`, confirm `one-bit-bureau motion status` reports `reduced`, and verify dock reveal, overview entry, active-app rail changes, previews, and secondary surfaces settle without magnification, spring, or nonessential transition. Run `one-bit-bureau motion full`, confirm status reports `full`, and verify the documented brief linear motion returns.

## Visual evidence

- Capture a clean One-Bit Bureau desktop at 16:9 with desktop objects and the launch shelf visible.
- Capture 16:10 and 21:9 desktops to inspect the protected icon lane, central application field, perimeter illustration crop, desktop icon bounds, and shelf placement. At least one non-16:9 capture must include a selected real photograph.
- Capture the overview, dock menu, icon manager in keyboard-focus and manual-association states, dock preview, app switcher, launcher, menu selected/disabled state, selected real photograph, unsupported-image fallback, notification, terminal ANSI palette, lock screen, and unlock picker.
- Capture the Inspector for a desktop object, dock application, and window; a two-item route slip; successful receipt and Undo; a rejected route; a cross-workspace Window Ledger; and the workspace board before and after a move.
- Record a short clip covering dock reveal/hide, app switching, and overview open/close.
- Keep `themes/one-bit-bureau/preview.png` honest as a wallpaper-only theme-picker preview. Keep the repository-root `preview.png` byte-identical to a reviewed real runtime capture for the plugin marketplace, and publish the rest of the labeled runtime evidence under `docs/screenshots/`.
- Record the public repository URL, release commit, Omarchy build, viewport geometry/scaling, lifecycle commands, and artifact hashes alongside the captures. A manually staged checkout, SVG proof, wallpaper crop, or `preview.png` is not lifecycle or runtime evidence.

## Release blockers

- Any overlap between desktop items and the top bar or dock.
- Dock or overview input regions that block unrelated windows when visually hidden.
- A stale `themes/one-bit-bureau/preview.png`, describing that wallpaper-only image as runtime evidence, or a repository-root `preview.png` that is not an exact reviewed runtime capture.
- A helper process that continues after the shell/plugin closes.
- Any keyboard trap, actionable secondary-surface control without a visible focus state and meaningful accessible name, or motion that continues after reduced motion is enabled.
- Any public lifecycle run that does not start from the GitHub URL, cannot align plugin and owned-theme commits, or fails to restore the recorded baseline on removal.
- An update that removes a previously published theme child or changes the public plugin ID.
- A claim that the dock has explicit monitor ownership before its persisted output resolver exists.
