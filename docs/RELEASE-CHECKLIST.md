# Release checklist

## Automated gate

- Run `bash tests/static.sh` from the repository root.
- Confirm `omarchy plugin validate .` passes on the target Omarchy release.
- Confirm the `paper-jam-84` theme passes strict validation and a real template render.
- Confirm the branded `unlock.png` has transparency and `preview-unlock.png` is 1920×1080 and matches the current mark.
- Confirm all twelve rendered app icons match `pack.json`, the font family names and checksums match `fonts/README.md`, and both license texts ship.
- Confirm the repository contains no symlinks or executable files; this is required because the same repository is also an Omarchy theme source.
- Review every bundled upstream diff and refresh `THIRD_PARTY_NOTICES.md` when importing updates.

## Disposable Omarchy runtime

- Install through the documented release path, `omarchy plugin add https://github.com/RegionallyFamous/paper-jam-84.git --yes && bash "$HOME/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/setup" --adopt-plugin`, not a manually copied directory.
- Verify the desktop service with an empty folder, many files, a long filename, a trusted launcher, an untrusted launcher, Trash, drag/drop, and two displays.
- Verify one click selects, a second click does not accidentally open, double-click and Return open, and clicking empty ground clears selection.
- Verify every generic object glyph—including the picture-file icon—inverts inside the ownership plate while meaningful application icons remain recognizable.
- Verify untrusted launchers default to Cancel, and both Enter and Escape cancel without executing the launcher.
- Verify dock launch, focus-existing-window, pin/unpin, reorder, auto-hide, previews, icon management, and the opt-in app-switcher binding in floating and tiled layouts.
- Verify automatic app-icon associations for Files, terminal, browser, and one communication app; then verify manual pack, native, and automatic modes without network access.
- Verify dock and desktop menus preserve their row order while unavailable commands remain visible and dimmed.
- Verify overview hot corner, summon/hide IPC, keyboard navigation, search, preview, close-window action, workspace changes, and two displays.
- Verify overview selection inverts only the ownership rail, the preview body remains stable, and the active window retains its separate double-rule marker.
- Verify active-app title truncation, an iconless app, an application with a changing title, vertical bar layout, and settings persistence.
- Verify stock Quick Look, launcher, clipboard, emoji menu, notifications, OSD, lock screen, and theme switching still work.
- Disable Paper Jam and confirm the stock bar and shell remain usable without restarting the machine; normal Alt+Tab must remain functional.
- With a desktop object, overview, and optional app-switcher focused in turn, verify native `Super + Arrow`, `Super + Tab`, `Super + Shift + Tab`, `Super + G`, `Super + O`, `Super + L`, and `Super + Grave` behavior still reaches Omarchy.
- Verify About/screensaver branding, both bundled fonts in `omarchy font list`, the unlock picker preview, and exact restoration of pre-install branding after removal.

## Visual evidence

- Capture a clean Paper Jam desktop at 16:9 with desktop objects and the launch shelf visible.
- Capture 16:10 and 21:9 desktops to inspect the protected icon lane, central application field, perimeter illustration crop, desktop icon bounds, and shelf placement.
- Capture the overview, dock preview, app switcher, launcher, menu selected state, notification, terminal ANSI palette, and lock screen.
- Record a short clip covering dock reveal/hide, app switching, and overview open/close.
- Keep the wallpaper-only `preview.png` honest as a theme-picker wallpaper preview; publish real runtime captures separately and label them as runtime evidence.

## Release blockers

- Any overlap between desktop items and the top bar or dock.
- Dock or overview input regions that block unrelated windows when visually hidden.
- A stale or wallpaper-only public preview.
- A helper process that continues after the shell/plugin closes.
- An update that removes a previously published theme child or changes the public plugin ID. The removed Alumina-era theme and plugin identities were unpublished development artifacts; local user-state files migrate non-destructively and are never deleted.
- A claim that the dock has explicit monitor ownership before its persisted output resolver exists.
