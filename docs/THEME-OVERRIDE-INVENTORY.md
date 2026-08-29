# Paper Jam ’84 native theme override inventory

Paper Jam uses native Omarchy theme files. The generated `colors.toml` baseline is not sufficient for the product’s opaque, square, compact shell contract, so the following narrow overrides are retained. This inventory records why each override exists and the runtime scene required to release it; it does not claim that the current static proofs are runtime evidence.

| Override | Why the generated/default surface is insufficient | Required runtime scene |
|---|---|---|
| `hyprland.lua` | The product requires 2px square frames, no blur, no shadow, full opacity, and compact gaps. These are compositor behaviors, not palette roles. | Tiled and floating active/inactive windows, popup, full-screen transition, theme switch. |
| `shell.bar.toml` | The top ownership rail must be opaque paper, compact, and stable rather than inheriting a translucent or differently sized generated bar. | Horizontal and vertical bar, active-app widget, long title, theme switch. |
| `shell.controls.toml` | Object-first focus requires single/2px carbon rules without filled hover decoration. Scalar generated defaults cannot express this restraint consistently. | Pointer hover, keyboard focus, selected and pressed controls on launcher/menu/settings. |
| `shell.font.toml` and `shell.spacing.toml` | The contact-sheet and workbench surfaces need one deliberate compact density while retaining the host font. | Menu, launcher, overview settings, long labels at 100% and fractional scale. |
| `shell.launcher.toml` and `shell.menu.toml` | Stable command inventory and ownership selection require opaque paper, full carbon inversion, and hard borders. | Launcher results, selected menu row, disabled row, submenu/dismissal. |
| `shell.popups.toml`, `shell.notifications.toml`, and `shell.tooltip.toml` | Generated surfaces may retain translucency or softer hierarchy; Paper Jam requires opaque paper alerts/popups and one carbon tooltip exception. | Notification with action, OSD/popup, tooltip over quiet and busy wallpaper. |
| `shell.image-picker.toml` | Actual thumbnails must stay readable inside explicit selected/unselected enclosures over an opaque scrim. | Wallpaper picker with photo, selected tile, keyboard focus, chaotic wallpaper. |
| `shell.lock.toml` and `shell.polkit.toml` | Authentication needs opaque paper, explicit error roles, and a 2px focus boundary without decorative color. | Lock idle/error/unlock and polkit idle/error/cancel. |

Files are removed when their semantics can be expressed faithfully by the native generated baseline. No override is justified solely because a static proof looks better with it.
