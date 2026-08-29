# Release checklist

## Automated gate

- Run `bash tests/static.sh` from the repository root.
- Confirm `omarchy plugin validate .` passes on the target Omarchy release.
- Confirm the `alumina-raster` theme passes strict validation and a real template render.
- Confirm the repository contains no symlinks or executable files; this is required because the same repository is also an Omarchy theme source.
- Review every bundled upstream diff and refresh `THIRD_PARTY_NOTICES.md` when importing updates.

## Disposable Omarchy runtime

- Install from the exact Git URL with `bash setup`, not a manually copied directory.
- Verify the desktop service with an empty folder, many files, a long filename, a trusted launcher, an untrusted launcher, Trash, drag/drop, and two displays.
- Verify dock launch, focus-existing-window, pin/unpin, reorder, auto-hide, previews, icon management, and Alt+Tab in floating and tiled layouts.
- Verify overview hot corner, summon/hide IPC, keyboard navigation, search, preview, close-window action, workspace changes, and two displays.
- Verify active-app title truncation, an iconless app, an application with a changing title, vertical bar layout, and settings persistence.
- Verify stock Quick Look, launcher, clipboard, emoji menu, notifications, OSD, lock screen, and theme switching still work.
- Disable Alumina and confirm the stock bar and shell remain usable without restarting the machine.

## Visual evidence

- Capture a clean Raster desktop at 16:9 with desktop objects and the launch shelf visible.
- Capture 16:10 and 21:9 desktops to inspect wallpaper crop, desktop icon bounds, and shelf placement.
- Capture the overview, dock preview, app switcher, launcher, menu selected state, notification, terminal ANSI palette, and lock screen.
- Record a short clip covering dock reveal/hide, app switching, and overview open/close.
- Keep the wallpaper-only `preview.png` honest as a theme-picker wallpaper preview; publish real runtime captures separately and label them as runtime evidence.

## Release blockers

- Any overlap between desktop items and the top bar or dock.
- Dock or overview input regions that block unrelated windows when visually hidden.
- A stale or wallpaper-only public preview.
- A helper process that continues after the shell/plugin closes.
- An update that removes an installed theme child or changes the permanent plugin ID.
- A claimed multi-monitor dock experience before the dock actually supports one surface per display.
