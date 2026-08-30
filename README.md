# Paper Jam ’84

Paper Jam ’84 is one installable Omarchy experience: real desktop files, a bottom application dock, a searchable window overview, active-application context in the top bar, a native theme, original bitmap branding, a bundled app-icon pack, and two legally redistributable retro monospace fonts.

It borrows the original Macintosh interface method rather than Apple artwork or exact trade dress. Select the object before acting, keep spatial landmarks stable, show immediate feedback, leave unavailable commands discoverable, and make the safe action obvious. The visual system uses original raster artwork, opaque paper-and-carbon surfaces, square geometry, and a two-color illustrated workbench.

![The twelve original Paper Jam app-role icons](docs/app-icon-pack.png)

The earlier modern Alumina edition remains preserved at the `alumina-modern-v1` Git tag. This unpublished vintage product now has a clean public identity throughout: repository `RegionallyFamous/paper-jam-84`, plugin ID `io.github.regionallyfamous.paper-jam-84`, and namespaced runtime state under `~/.config/omarchy/paper-jam-84/`. Setup non-destructively copies any local Alumina-era pins, settings, icon mappings, icon files, and desktop positions forward when the new destination does not already exist.

## What is included

- Real files and folders from the configured XDG Desktop directory on every display, with selection, keyboard opening, drag/drop, Trash, safe launcher confirmation, persistent positions, and original bitmap object icons—including a dedicated picture-file icon rather than a literal photo tile.
- A bottom dock with launch/focus, running indicators, auto-hide, pinning, reordering, previews, one-output ownership, and an optional app-switcher HUD.
- Twelve original offline Paper Jam app-role icons, automatic matching for common Linux desktop IDs, manual association, an explicit native-icon override, and compatibility with migrated local icon mappings.
- A searchable, keyboard-navigable contact-sheet overview with live window previews and a top-left hot corner.
- A native bar widget placed beside the Omarchy menu; Paper Jam leaves the rest of Omarchy’s top bar intact.
- The `paper-jam-84` theme with a 4K Bitmap Workbench background, opaque square shell surfaces, and a branded unlock mark plus honest 1920×1080 unlock preview.
- Original About and screensaver text branding generated through Omarchy’s own image-to-text pipeline.
- Monaspace Krypton NF 1.400 and Departure Mono 1.500, with exact upstream licenses and SHA-256 checksums under `fonts/`.

The product contract and provenance guardrails live in [docs/DIRECTION.md](docs/DIRECTION.md). Imported-code and font provenance lives in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Install: Git and Omarchy, no pipe-to-shell

Paper Jam uses Omarchy’s own validated Git plugin flow, then adopts that disabled checkout to install the matching source-owned theme and reversible companion assets:

```bash
omarchy plugin add https://github.com/RegionallyFamous/paper-jam-84.git --yes && bash "$HOME/.config/omarchy/plugins/io.github.regionallyfamous.paper-jam-84/setup" --adopt-plugin
```

This keeps the source auditable in a normal Git checkout, uses Omarchy’s manifest validator before any Paper Jam code runs, and avoids downloading an opaque bootstrap script. The first command leaves the validated plugin disabled; setup then presents one explicit unsandboxed-plugin warning and lists the system changes before it enables anything. Declining removes that disabled checkout. After independently reviewing the repository, a noninteractive install may append `--yes` to the setup command. Setup also verifies the canonical repository identity and commit, refuses enabled standalone replacements, records exact ownership, and rolls back a partial transaction.

Paper Jam targets the current Omarchy Quattro plugin API and relies on Omarchy’s default runtime tools (`python3` with Gio bindings, `hyprctl`, `jq`, Git, coreutils, and fontconfig). Disable `henri.desktop-icons`, `crmne.active-window`, `expose.window-overview`, and `rosakodu.dock` first; setup refuses an enabled conflict instead of silently doubling shell surfaces.

For development from this checkout:

```bash
bash setup --local
```

## What setup changes

- Installs and enables `io.github.regionallyfamous.paper-jam-84` with its native bar widget in the left section after `omarchy.menu`.
- Installs `paper-jam-84` through Omarchy’s theme-source ownership system, puts the bar at the top, makes it opaque, and applies the theme.
- Installs both bundled fonts under `~/.local/share/fonts/paper-jam-84/` and refreshes fontconfig, without selecting a font or rewriting terminal configuration.
- Backs up and applies Paper Jam About/screensaver branding. Removal restores the exact prior bytes only while Paper Jam still owns the active files; a later user edit is preserved.
- Installs the `paper-jam` coordinator into `~/.local/bin/` and creates the already-configured XDG Desktop directory when needed. It does not rewrite `XDG_DESKTOP_DIR`, Hyprland bindings, or input policy.
- Ships unlock branding inside the theme but does not run privileged Plymouth/initramfs commands. Choose it through Omarchy’s Style → Unlock surface when desired.

## The Paper Jam command

```bash
paper-jam status
paper-jam update
paper-jam remove
paper-jam overview
paper-jam icon pack list
paper-jam icon pack set org.gnome.Nautilus files
paper-jam icon native firefox
paper-jam icon auto firefox
paper-jam font list
paper-jam font use krypton
```

`paper-jam update` updates only this Git-managed plugin and its recorded theme source, checks that both reach the same commit, and reapplies the theme only when it was already active. `paper-jam font use krypton` delegates to Omarchy’s supported font setter; Krypton is the recommended whole-desktop choice because it includes Nerd Font symbols. Departure Mono is the more aggressively pixel-shaped alternate and does not include those symbols.

## Omarchy navigation remains Omarchy navigation

Paper Jam adds mouse-friendly discovery without replacing Omarchy’s keyboard-first model. Focused Paper Jam surfaces explicitly pass every `Super`-modified chord through to the compositor, so the native tiling, workspace, grouping, popped-window, fullscreen, and scratchpad commands remain authoritative.

| Intent | Control |
|---|---|
| Omarchy menu | `Super + Space` |
| Terminal / browser | `Super + Return` / `Super + Shift + Return` |
| Move focus / swap windows | `Super + Arrow` / `Super + Shift + Arrow` |
| Toggle stack, float, fullscreen | `Super + J`, `Super + T`, `Super + F` |
| Toggle workspace layout / group / popped window | `Super + L`, `Super + G`, `Super + O` |
| Scratchpad | `Super + Grave` or `Super + S` |
| Select / open a desktop object | Single click; then `Return`, or double-click |
| Show all windows | Top-left hot corner or `paper-jam overview` |
| Preview a selected overview window | `Space` |
| Change background | `Super + Ctrl + Space` |

Paper Jam does not replace global Alt+Tab. An optional Paper Jam HUD can live on the non-conflicting `Alt + Grave` chord by adding this user-owned snippet to `~/.config/hypr/bindings.lua`:

```lua
o.bind("ALT + GRAVE", "Paper Jam app switcher next", "omarchy-shell -q regionallyfamous.paper-jam-84.dock altTabNext")
o.bind("ALT + SHIFT + GRAVE", "Paper Jam app switcher previous", "omarchy-shell -q regionallyfamous.paper-jam-84.dock altTabPrev")
```

An optional overview binding can use `Ctrl + Up` without taking a `Super` chord:

```lua
o.bind("CTRL + UP", "Paper Jam window overview", hl.dsp.event("regionallyfamous.paper-jam-84.overview:toggle"))
```

## Official Omarchy contracts covered

Paper Jam follows the documented native boundaries for [themes](https://omarchy.org/manual/themes/), [backgrounds](https://omarchy.org/manual/backgrounds/), [branding](https://omarchy.org/manual/branding/), [fonts](https://omarchy.org/manual/fonts/), [the top bar](https://omarchy.org/manual/the-top-bar/), and [navigation](https://omarchy.org/manual/navigation/). Theme colors drive Omarchy’s normal app and shell templates; backgrounds remain selectable; unlock assets use the documented filenames; the bar widget uses native placement and `shell.json`; fonts remain fontconfig/Omarchy-managed; and Paper Jam does not seize the system’s navigation language.

## Network and permissions

The plugin runs with the current user’s shell privileges. It reads the configured Desktop directory, writes user state only under `~/.config/omarchy/paper-jam-84/`, launches selected files through Gio, and calls standard Omarchy/Hyprland helpers. Copied `.desktop` launchers remain untrusted unless they came from canonical application directories; trusting one requires explicit confirmation.

The bundled app-icon pack and automatic associations work entirely offline. Manage Icons filters the twelve original Paper Jam roles locally and can switch any app back to its native icon. Paper Jam does not send app names to an icon service or download third-party artwork.

## Known boundaries

- The dock owns one persisted output. Set it with `paper-jam dock setScreen DP-1`; if that output disconnects, Paper Jam falls back safely and returns when it reconnects.
- Linux client-side decorations remain application-owned, so no shell plugin can make every title bar match.
- The dock is a modern launcher translated into Paper Jam’s object-first system, not a claim of historical 1984 behavior.
- PNGs under `docs/` are labeled static design proofs. Public runtime claims remain gated on the disposable x86_64 Omarchy acceptance run and captures from the exact release artifact.

## Validate

```bash
bash tests/static.sh
```

The local gate covers manifest and source safety, helper syntax, desktop trust/path policy, dock lifecycle and app association, setup/uninstall rollback, branding/font ownership, namespace migration, strict theme validation, headless template rendering, and navigation pass-through contracts. The graphical gate is `bash test/omarchy-acceptance.sh` inside the disposable x86_64 Omarchy guest.

## Remove

```bash
paper-jam remove
```

Removal is ownership-aware. It restores prior theme, bar, and branding state only while Paper Jam still owns the active value; detaches only the theme child owned by the recorded Git source; removes unmodified bundled fonts and command; and preserves Desktop files, pins, icon choices, custom icons, and desktop positions.
