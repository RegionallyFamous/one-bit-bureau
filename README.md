# Alumina

Alumina is one cohesive Mac-like experience for Omarchy: desktop files, a glass dock with app switching and previews, a searchable window overview, active-application context in the top bar, and matching light and dark native themes.

It is intentionally Mac-familiar rather than a pixel copy. Alumina keeps Omarchy's tiling model, launcher, Quick Look, control panels, screenshots, and update path while adding the interaction landmarks a Mac user expects.

## What is included

- Real `~/Desktop` files and folders on every display, including drag/drop, context menus, Trash, launchers, and persistent positions.
- A bottom dock initially pinned with Files, Chromium, and Foot, plus running indicators, auto-hide, window previews, custom icons, and a macOS-like Alt+Tab app switcher.
- A searchable, keyboard-navigable window overview with live previews and a top-left hot corner.
- The current application icon and title beside the Omarchy menu.
- `alumina-dark` and `alumina-light` theme variants with original 4K wallpaper, translucent shell surfaces, squircle-like corners, soft shadow, and restrained blue focus states.
- One setup command that installs the plugin and theme from the same Git repository.

The product direction and explicit non-goals live in [docs/DIRECTION.md](docs/DIRECTION.md). Source provenance lives in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Install

Publish this directory as a Git repository, then clone it and run:

```bash
git clone <your-alumina-repository-url> alumina
cd alumina
bash setup
```

Use the light theme instead:

```bash
bash setup --light
```

For development from this folder without a standalone Git remote:

```bash
bash setup --local
```

The setup command:

1. validates and installs `io.github.regionallyfamous.alumina`;
2. enables it in the left bar section after `omarchy.menu`;
3. installs and applies the selected native theme;
4. creates `~/Desktop` and points the XDG desktop directory at it;
5. keeps the top bar at the top and enables its transparent material mode.

It does not install packages, use privilege escalation, edit application titlebars, or delete user files.

## Familiar controls

| Intent | Alumina / Omarchy control |
|---|---|
| Launch an app like Spotlight | `Super + Space` |
| Switch applications | `Alt + Tab` / `Alt + Shift + Tab` |
| Show all windows | Move to the top-left hot corner, or run `omarchy-shell shell toggle io.github.regionallyfamous.alumina '{}'` |
| Quick Look a selected file | `Space` in Files or the overview |
| Change wallpaper | `Super + Ctrl + Space` |
| Open system controls | Use the right side of the top bar |
| Move between Spaces | Omarchy workspace shortcuts or an optional touchpad gesture below |

## Optional Mac-like input settings

Alumina does not silently rewrite `~/.config/hypr/input.lua`. Add this to that file if you want natural scrolling and a four-finger horizontal Spaces gesture:

```lua
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
```

On a PC keyboard, add `altwin:swap_alt_win` to your existing `kb_options` only if you deliberately want Alt to act like Command. Do not add it on Apple hardware without first checking how the keyboard already maps Command.

For a persistent overview shortcut, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + UP", "Window overview", hl.dsp.event("regionallyfamous.alumina.overview:toggle"))
```

Then run `hyprctl reload`.

## Known boundaries

- The dock currently appears on the primary display; desktop files and the overview support multiple displays.
- Linux client-side window decorations are owned by each application, so Alumina cannot reliably add universal red/yellow/green titlebar controls.
- A universal global application menu is deliberately omitted because the available bridge is not mature enough to justify an unaudited binary in a long-lived shell.
- Alumina does not globally float windows. Per-application floating rules are a better fit for utilities that genuinely need them.
- The dock's online icon search is optional and contacts macOSicons.com only when the user opens Manage Icons and performs a search.

## Validate

From an Omarchy checkout containing the current plugin validator:

```bash
bash tests/static.sh
```

The automated gate covers manifest validation, shell and helper syntax, bundled model tests, strict theme validation, template rendering, source safety, and unresolved legacy IDs. A public release still needs visual verification in a real x86_64 Omarchy session; see [docs/RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md).

## Remove

```bash
bash uninstall
```

Removal leaves `~/Desktop`, desktop files, pinned-dock state, and custom icon files intact. The script prints their paths so you can decide whether to keep them.
