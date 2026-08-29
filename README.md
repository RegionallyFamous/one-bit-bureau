# Paper Jam ’84

Paper Jam ’84 is one installable Omarchy experience: real desktop files, a bottom application dock, a searchable window overview, active-application context in the top rail, and one matching `paper-jam-84` native theme.

It borrows the original Macintosh interface method rather than Apple’s artwork or exact trade dress. Select the object before acting, keep spatial landmarks stable, show immediate feedback, leave unavailable commands discoverable, and make the safe action obvious. The visual system uses original raster artwork, opaque paper-and-carbon surfaces, square geometry, restrained modern color, and a two-color illustrated workbench.

The tested modern Alumina edition remains preserved at the `alumina-modern-v1` Git tag. Paper Jam keeps the internal plugin ID `io.github.regionallyfamous.alumina`, IPC targets, layer namespaces, and existing `alumina-*` state filenames so upgrades do not discard user state.

## What is included

- Real files and folders from the configured XDG Desktop directory on every display, with single-click selection, double-click open, keyboard opening, drag/drop, Trash, safe launcher confirmation, persistent positions, and original bitmap object icons—including a dedicated picture-file icon instead of live photo thumbnails.
- A bottom application dock seeded with Files, Chromium, and Foot, plus running indicators, auto-hide, pinning, reordering, custom icons, window previews, and an optional app-switcher HUD.
- A searchable, keyboard-navigable contact-sheet window overview with live previews and a top-left hot corner.
- The active application owner and secondary window title beside the Omarchy menu.
- The `paper-jam-84` native theme, with an original two-color 4K Bitmap Workbench wallpaper and fully opaque square shell surfaces.
- Preserved ImageGen masters, prompts, and deterministic raster reductions under `artwork/`.

The product contract and provenance guardrails live in [docs/DIRECTION.md](docs/DIRECTION.md). Imported-code provenance lives in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Install

The public repository must ship Paper Jam on its default branch before remote installation is offered. The setup script refuses to install a different checked-out branch through a default-branch clone, preventing a partial or mismatched experience.

Paper Jam targets the current Omarchy Quattro plugin API and relies on Omarchy’s default runtime tools (`python3` with Gio bindings, `grim`, ImageMagick, `hyprctl`, `jq`, and `timeout`). The final supported-release claim remains gated on the disposable x86_64 runtime run described below.

Disable the standalone `henri.desktop-icons`, `crmne.active-window`, `expose.window-overview`, and `rosakodu.dock` plugins before setup. Paper Jam replaces those four surfaces as one coordinated package, and setup refuses an enabled conflict instead of silently producing a partial or doubled shell.

For development from this checkout:

```bash
bash setup --local
```

Setup stages a minimal plugin payload, removes repository/test debris, validates it, and atomically moves it into place. It then installs the one matching theme, enables the active-application widget, puts the bar at the top, makes it opaque, applies the theme, and creates the already-configured XDG Desktop directory when needed. It does not rewrite `XDG_DESKTOP_DIR`.

Setup refuses existing plugin/theme collisions and records exactly what it created plus the previous theme and bar settings. A failure rolls back the partial install. Uninstall restores a previous setting only while Paper Jam still owns its current value.

## Familiar controls

| Intent | Paper Jam / Omarchy control |
|---|---|
| Select a desktop object | Single click |
| Open a desktop object | Double-click, or select it and press `Return` |
| Launch an application | `Super + Space` |
| Switch windows | Omarchy’s existing `Alt + Tab` behavior |
| Show all windows | Move to the top-left hot corner, or run `omarchy-shell shell toggle io.github.regionallyfamous.alumina '{}'` |
| Preview a selected window | Press `Space` in the overview |
| Quick Look a selected file | Press `Space` in Files |
| Change wallpaper | `Super + Ctrl + Space` |
| Open system controls | Use the right side of the top rail |
| Move between workspaces | Omarchy workspace shortcuts |

## Optional persistent bindings

Paper Jam deliberately does not replace global Alt+Tab bindings at runtime. That keeps disabling or removing the plugin from leaving dead compositor shortcuts. To opt into its app-switcher HUD on `Alt + Grave`, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + GRAVE", "Paper Jam app switcher next", "omarchy-shell -q regionallyfamous.alumina.dock altTabNext")
o.bind("ALT + SHIFT + GRAVE", "Paper Jam app switcher previous", "omarchy-shell -q regionallyfamous.alumina.dock altTabPrev")
```

For a persistent overview shortcut:

```lua
o.bind("CTRL + UP", "Paper Jam window overview", hl.dsp.event("regionallyfamous.alumina.overview:toggle"))
```

Then run `hyprctl reload`.

Paper Jam also leaves `~/.config/hypr/input.lua` alone. Natural scrolling, click-finger behavior, and workspace gestures remain the user’s input-policy choice.

## Network and permissions

The plugin runs with the current user’s shell privileges. It reads the configured Desktop directory, writes desktop-position and dock-state files under `~/.config/omarchy/`, launches selected files through Gio, and calls standard Omarchy/Hyprland helpers. Copied `.desktop` launchers remain untrusted unless they came from canonical application directories; trusting one requires the explicit confirmation surface.

The optional dock icon search contacts macOSicons.com only after the user opens Manage Icons and searches. Applying an arbitrary icon URL downloads the selected image into the user’s Omarchy icon directory. No network call is required for normal dock, desktop, overview, or theme operation.

## Known boundaries

- The dock owns one persisted output and keeps every dock surface on that output. Set it with `omarchy-shell regionallyfamous.alumina.dock setScreen DP-1`; if that output disconnects, Paper Jam safely falls back to the first available output and returns when it reconnects.
- Linux client-side decorations remain application-owned, so the plugin cannot make every title bar match.
- The dock is a modern launcher translated into the Paper Jam system, not a claim of historical 1984 behavior.
- Runtime release evidence still requires the disposable x86_64 Omarchy guest; the PNGs under `docs/` are clearly labeled static design proofs.

## Validate

From this checkout:

```bash
bash tests/static.sh
```

The local gate covers manifest validation, shell/helper syntax, desktop trust/path policy tests, dock model and lifecycle-contract tests, strict theme validation, template rendering, source safety, and unresolved legacy identities. A public release also requires `bash test/omarchy-acceptance.sh` inside the disposable x86_64 Omarchy guest and real runtime captures from the exact release artifact.

## Update and remove

Git-managed public installs update through Omarchy’s normal plugin and theme update commands after the release repository exists:

```bash
omarchy plugin update io.github.regionallyfamous.alumina
omarchy theme update
```

Remove an installation created by the setup script with:

```bash
bash uninstall
```

Uninstall refuses to remove anything without a valid ownership record. It preserves Desktop files, dock pins, custom icons, and desktop positions, and restores only Paper Jam-owned theme/bar changes that the user has not since changed.
