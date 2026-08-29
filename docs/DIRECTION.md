# Alumina direction contract

## Product sentence

Alumina should feel immediately legible to a Mac user while remaining recognizably Omarchy: fast, keyboard-capable, composable, and recoverable.

## Named visual laws

1. **Quiet chrome, vivid content.** Shell surfaces use low-contrast graphite or pearl glass; application icons and wallpaper refractions carry the stronger color.
2. **Squircle rhythm.** Floating surfaces use soft continuous-looking corners, moderate gaps, and a restrained one-pixel edge instead of heavy borders.
3. **One depth system.** Bar, dock, menus, launcher, overview cards, and notifications share translucent material, soft shadow, and the same blue focus logic.
4. **Top context, bottom action.** The top bar identifies the active application and system state; the dock owns launching, switching, pinning, and previews.
5. **Wallpaper yields to work.** The upper-left remains calm for desktop items, the center tolerates windows, and the visual mass stays low and right.

## Interaction laws

- Desktop files are real files in `~/Desktop`, not a second database.
- The dock auto-hides, preserves pin order, previews windows, and owns the app-switcher HUD.
- The overview is searchable, keyboard navigable, and available from the top-left hot corner; a persistent key binding remains an explicit user choice until Omarchy exposes dependency-safe binding metadata.
- Quick Look stays Omarchy-native through Sushi and the Space key; Alumina does not replace it.
- Tiling stays the default window model. Alumina adds familiar surfaces without forcing every application to float.

## Palette roles

- Dark base: graphite, blue-black, and cool slate.
- Light base: pearl, cool silver, and soft graphite.
- Focus/accent: restrained system blue.
- Urgent: warm coral red.
- Success: clean green.
- Warning: amber.
- Secondary atmosphere: violet and cyan, used sparingly.

## Non-goals

- Pixel-perfect macOS imitation.
- Apple logos, proprietary icons, San Francisco font redistribution, or copied wallpaper compositions.
- Universal traffic-light titlebar buttons; application decorations are client-owned on Linux.
- A global application menu bridge with an unaudited binary dependency.
- A globally floating desktop that discards Omarchy's tiling strengths.

## Success checks

- A Mac user can find files, launch or switch apps, expose windows, preview files, and locate system state without documentation.
- The desktop remains usable with the companion theme disabled.
- Disabling the plugin restores the stock shell without deleting user files or pinned-app state.
- Both themes retain readable primary and selection text and keep the wallpaper quiet at 16:9, 16:10, and ultrawide crops.
