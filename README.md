# Alumina Raster

Alumina Raster is an object-first, one-bit-inspired edition of the Alumina experience for Omarchy. Its Bitmap Workbench revision combines real desktop files, expressive ImageGen-authored raster objects, a hard-edged launch shelf with app switching and previews, a contact-sheet window overview, application-first context in the top rail, and one matching native theme.

It applies the original Macintosh interface method rather than copying Apple's artwork or exact trade dress: select an object before acting, keep spatial landmarks stable, provide immediate feedback, retain unavailable commands in place, and make safe actions obvious. The edition uses original ImageGen-authored bitmap illustration, opaque paper-and-carbon surfaces, square geometry, compact spacing, and grayscale-first shell state while keeping Omarchy's tiling model and modern Linux behavior.

The tested modern Alumina build remains preserved at the `alumina-modern-v1` Git tag. This branch is an alternative edition of the same plugin ID, not a side-by-side install.

## What is included

- Real `~/Desktop` files and folders on every display, including single-click selection, double-click open, drag/drop, stable context menus, Trash, launchers, and persistent positions.
- A bottom launch shelf pinned initially with Files, Chromium, and Foot, plus running indicators, auto-hide, window previews, custom icons, and an Alt+Tab app switcher.
- A searchable, keyboard-navigable window overview with live previews and a top-left hot corner.
- The current application owner and secondary window title beside the Omarchy menu.
- The `alumina-raster` native theme, with an original two-color 4K Bitmap Workbench wallpaper and fully opaque square shell surfaces.
- Preserved ImageGen wallpaper and object-atlas masters, prompts, and deterministic raster reductions under `artwork/`.

The product direction and explicit provenance guardrails live in [docs/DIRECTION.md](docs/DIRECTION.md). Third-party code provenance lives in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Install

Publish or clone this branch as a Git repository, then run:

```bash
git clone --branch codex/vintage-1984 <your-alumina-repository-url> alumina-raster
cd alumina-raster
bash setup
```

For development from this folder without a standalone Git remote:

```bash
bash setup --local
```

The setup command validates and installs `io.github.regionallyfamous.alumina`, installs and applies `alumina-raster`, creates the XDG desktop directory, places the active-application widget after the Omarchy menu, and keeps the top rail opaque.

Because the modern and Raster editions intentionally share one plugin ID, switch an installed checkout to the desired Git branch or remove the installed edition before adding the other. Do not enable two Alumina checkouts at once.

## Familiar controls

| Intent | Alumina Raster / Omarchy control |
|---|---|
| Select a desktop object | Single click |
| Open a desktop object | Double-click, or select it and press `Return` |
| Launch an application | `Super + Space` |
| Switch applications | `Alt + Tab` / `Alt + Shift + Tab` |
| Show all windows | Move to the top-left hot corner, or run `omarchy-shell shell toggle io.github.regionallyfamous.alumina '{}'` |
| Quick Look a selected file | `Space` in Files or the overview |
| Change wallpaper | `Super + Ctrl + Space` |
| Open system controls | Use the right side of the top rail |
| Move between workspaces | Omarchy workspace shortcuts |

## Optional input settings

Alumina Raster does not silently rewrite `~/.config/hypr/input.lua`. Add this if you want natural scrolling and a four-finger horizontal workspace gesture:

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

For a persistent overview shortcut, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + UP", "Window overview", hl.dsp.event("regionallyfamous.alumina.overview:toggle"))
```

Then run `hyprctl reload`.

## Known boundaries

- The launch shelf currently appears on the primary display; desktop files and the overview support multiple displays.
- Linux client-side window decorations remain application-owned, so the plugin cannot make every title bar match.
- The dock is a modern launcher rendered through the Raster system, not a claim of historical accuracy.
- The dock's optional online icon search contacts macOSicons.com only when the user opens Manage Icons and performs a search.

## Validate

From this checkout:

```bash
bash tests/static.sh
```

The local gate covers manifest validation, shell and helper syntax, bundled model tests, strict theme validation, template rendering, source safety, and unresolved legacy identities. Real runtime evidence is captured separately in a disposable x86_64 Omarchy VM and is never replaced by the wallpaper preview or deterministic theme proof.

The repository includes explicitly labeled, non-runtime design artifacts for local review. They are never substitutes for installed runtime evidence.

## Remove

```bash
bash uninstall
```

Removal leaves `~/Desktop`, desktop files, pinned-shelf state, and custom icon files intact. The script prints their paths so you can decide whether to keep them.
