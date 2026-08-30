# Release checklist

## Automated gate

- Run `bash tests/static.sh` from the repository root.
- Confirm `omarchy plugin validate .` passes on the target Omarchy release.
- Confirm the `one-bit-bureau` theme passes strict validation and a real template render.
- Confirm the branded `unlock.png` has transparency and `preview-unlock.png` is 1920×1080 and matches the current mark.
- Confirm all twelve rendered app icons match `pack.json`, the font family names and checksums match `fonts/README.md`, and both license texts ship.
- Confirm the desktop policy exposes only regular local PNG, JPEG, WebP, and BMP files at or below 32 MiB as previews; SVG, GIF, oversized, remote, inline, missing, and disallowed-path inputs must fall back without being decoded by the shell.
- Confirm the repository contains no symlinks or executable files; this is required because the same repository is also an Omarchy theme source.
- Run `npm --prefix shortlink ci`, `npm --prefix shortlink test`, remove the generated `shortlink/node_modules`, and then run the repository static gate. Confirm the Worker typecheck, routes, methods, redirects, bootstrap behavior, and plugin/theme source-safety checks all pass.
- Compare the live `https://bureau.regionallyfamous.com/install` bytes with `shortlink/src/install.sh`, run `bash -n` against the live response, and verify the landing page, canonical source/release redirects, 404/405 behavior, HTTPS certificate, and response security headers.
- Review every bundled upstream diff and refresh `THIRD_PARTY_NOTICES.md` when importing updates.

## Exact public lifecycle in a disposable Omarchy guest

- Start from a clean guest and record the active theme, bar position/transparency, presence and SHA-256 hashes of `~/.config/omarchy/branding/about.txt` and `screensaver.txt`, selected Omarchy font, and whether the One-Bit Bureau command, plugin, theme, source, ownership record, and font directory already exist.
- Install from the public repository with `omarchy plugin add https://github.com/RegionallyFamous/one-bit-bureau.git --yes`. Confirm the validated checkout is present but disabled and that no theme, font, branding, bar, command, or ownership state changed before setup.
- Adopt and activate that exact checkout with `bash "$HOME/.config/omarchy/plugins/io.github.regionallyfamous.one-bit-bureau/setup" --adopt-plugin --yes`. Confirm the plugin is enabled, the owned `one-bit-bureau` theme is active, the recorded theme mode is `source` on hosts with the native theme-source API or `plugin-link` on earlier Quattro hosts, the theme and plugin resolve to the same commit, the top opaque bar and One-Bit Bureau branding are active, both font families are visible to fontconfig, and the previously selected Omarchy font remains selected.
- Run `one-bit-bureau status`, then `one-bit-bureau update --yes`. Confirm the plugin checkout, recorded plugin commit, owned theme installation, and recorded theme commit resolve to the same final release commit; an already active One-Bit Bureau theme must remain active.
- Run `one-bit-bureau remove`. Confirm the plugin payload, owned theme link and any source child, unmodified bundled font directory, unmodified command, and ownership record are gone; the recorded theme, bar settings, and exact prior branding bytes are restored; the selected font is unchanged; and the documented Desktop files, pins, icon choices, custom icons, and positions remain as user data.
- Repeat the branding removal check after editing one installed branding file. Removal must preserve that later edit and retain its corresponding backup rather than overwriting it.

## Disposable Omarchy runtime behavior

- Verify the desktop service with an empty folder, many files, a long filename, a trusted launcher, an untrusted launcher, Trash, drag/drop, and two displays.
- Verify one click selects, a second click does not accidentally open, double-click and Return open, and clicking empty ground clears selection.
- Verify safe local photographs render as stable grayscale desktop thumbnails; selecting one changes only its enclosing rule and name rail, the source file remains byte-identical, and opening it shows the original color image. Verify unsupported and unsafe images use the authored one-bit picture fallback, which reverses with its name rail.
- Verify untrusted launchers default to Cancel, and both Enter and Escape cancel without executing the launcher.
- Verify the clean first-run dock seeds Files, Chromium, and Foot; all three use their One-Bit Bureau associations, painted-alpha crops, 48px boxes, and a shared optical center without clipping or crowding.
- Verify dock launch, focus-existing-window, pin/unpin, reorder, auto-hide, previews, icon management, and the opt-in app-switcher binding in floating and tiled layouts.
- Verify automatic app-icon associations for Files, terminal, browser, and one communication app. Add an unmatched app and confirm its automatic native fallback is grayscale in the dock, drag ghost, preview fallback, app switcher, and icon manager; then confirm explicit Native mode restores the original color and custom files plus manual pack choices render as supplied, all without network access.
- Verify dock and desktop menus preserve their row order while unavailable commands remain visible and dimmed.
- Verify overview hot corner, summon/hide IPC, keyboard navigation, search, preview, close-window action, workspace changes, and two displays.
- Verify overview selection inverts only the ownership rail, the preview body remains stable, and the active window retains its separate double-rule marker.
- Verify active-app title truncation, an iconless app, an application with a changing title, vertical bar layout, and settings persistence.
- Verify stock Quick Look, launcher, clipboard, emoji menu, notifications, OSD, lock screen, and theme switching still work.
- Disable One-Bit Bureau and confirm the stock bar and shell remain usable without restarting the machine; normal Alt+Tab must remain functional.
- With a desktop object, overview, and optional app-switcher focused in turn, verify native `Super + Arrow`, `Super + Tab`, `Super + Shift + Tab`, `Super + G`, `Super + O`, `Super + L`, and `Super + Grave` behavior still reaches Omarchy.
- Verify About/screensaver branding, both bundled fonts in `omarchy font list`, the unlock picker preview, and exact restoration of pre-install branding after removal.
- Drive the dock menu and icon manager without a pointer. Verify logical Tab/Shift+Tab and arrow traversal, Enter/Space activation, Escape dismissal, visible focus on every actionable control, readable assistive-technology names/roles, and practical pointer targets that do not visually inflate the compact controls.
- Run `one-bit-bureau motion reduce`, confirm `one-bit-bureau motion status` reports `reduced`, and verify dock reveal, overview entry, active-app rail changes, previews, and secondary surfaces settle without magnification, spring, or nonessential transition. Run `one-bit-bureau motion full`, confirm status reports `full`, and verify the documented brief linear motion returns.

## Visual evidence

- Capture a clean One-Bit Bureau desktop at 16:9 with desktop objects and the launch shelf visible.
- Capture 16:10 and 21:9 desktops to inspect the protected icon lane, central application field, perimeter illustration crop, desktop icon bounds, and shelf placement. At least one non-16:9 capture must include a selected real photograph.
- Capture the overview, dock menu, icon manager in keyboard-focus and manual-association states, dock preview, app switcher, launcher, menu selected/disabled state, selected real photograph, unsupported-image fallback, notification, terminal ANSI palette, lock screen, and unlock picker.
- Record a short clip covering dock reveal/hide, app switching, and overview open/close.
- Keep the wallpaper-only `preview.png` honest as a theme-picker wallpaper preview; publish real runtime captures separately and label them as runtime evidence.
- Record the public repository URL, release commit, Omarchy build, viewport geometry/scaling, lifecycle commands, and artifact hashes alongside the captures. A manually staged checkout, SVG proof, wallpaper crop, or `preview.png` is not lifecycle or runtime evidence.

## Release blockers

- Any overlap between desktop items and the top bar or dock.
- Dock or overview input regions that block unrelated windows when visually hidden.
- A stale `preview.png`, or describing its wallpaper-only image as a runtime desktop capture.
- A helper process that continues after the shell/plugin closes.
- Any keyboard trap, actionable secondary-surface control without a visible focus state and meaningful accessible name, or motion that continues after reduced motion is enabled.
- Any public lifecycle run that does not start from the GitHub URL, cannot align plugin and owned-theme commits, or fails to restore the recorded baseline on removal.
- An update that removes a previously published theme child or changes the public plugin ID.
- A claim that the dock has explicit monitor ownership before its persisted output resolver exists.
