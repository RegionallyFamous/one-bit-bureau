# Release checklist

## Automated gate

- Run `bash tests/static.sh` from the repository root.
- Confirm `omarchy plugin validate .` passes on the target Omarchy release.
- Confirm the `paper-jam-84` theme passes strict validation and a real template render.
- Confirm the repository contains no symlinks or executable files; this is required because the same repository is also an Omarchy theme source.
- Review every bundled upstream diff and refresh `THIRD_PARTY_NOTICES.md` when importing updates.

## Disposable Omarchy runtime

- Install from the exact Git URL with `bash setup`, not a manually copied directory.
- Verify the desktop service with an empty folder, many files, a long filename, a trusted launcher, an untrusted launcher, Trash, drag/drop, and two displays.
- Verify one click selects, a second click does not accidentally open, double-click and Return open, and clicking empty ground clears selection.
- Verify every generic object glyph—including the picture-file icon—inverts inside the ownership plate while meaningful application icons remain recognizable.
- Verify untrusted launchers default to Cancel, and both Enter and Escape cancel without executing the launcher.
- Verify dock launch, focus-existing-window, pin/unpin, reorder, auto-hide, previews, icon management, and the opt-in app-switcher binding in floating and tiled layouts.
- Verify dock and desktop menus preserve their row order while unavailable commands remain visible and dimmed.
- Verify overview hot corner, summon/hide IPC, keyboard navigation, search, preview, close-window action, workspace changes, and two displays.
- Verify overview selection inverts only the ownership rail, the preview body remains stable, and the active window retains its separate double-rule marker.
- Verify active-app title truncation, an iconless app, an application with a changing title, vertical bar layout, and settings persistence.
- Verify stock Quick Look, launcher, clipboard, emoji menu, notifications, OSD, lock screen, and theme switching still work.
- Disable Paper Jam and confirm the stock bar and shell remain usable without restarting the machine; normal Alt+Tab must remain functional.

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
- An update that removes a previously published theme child or changes the permanent plugin ID. If `alumina-raster` is ever distributed before this release, add and test a migration before removing that child; an unpublished development child requires no compatibility payload.
- A claim that the dock has explicit monitor ownership before its persisted output resolver exists.
