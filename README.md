# One-Bit Bureau

**One command turns Omarchy into a one-bit Macintosh-inspired workbench.**

You get real folders on the desktop, a bottom dock, one shared Inspector, safe file routing with Undo, a window ledger, a workspace board, original bitmap icons, a matching whole-desktop theme, retro fonts, and One-Bit Bureau branding—all installed and updated together.

[Install](#install) · [See everything it includes](#what-you-get) · [Read the Wiki](https://github.com/RegionallyFamous/one-bit-bureau/wiki) · [Latest release](https://github.com/RegionallyFamous/one-bit-bureau/releases/latest)

![One-Bit Bureau desktop with real files, a grayscale photo preview, the Bitmap Workbench background, top bar, and bottom dock](docs/screenshots/runtime-desktop.png)

## Install

One-Bit Bureau requires a current Omarchy Quattro installation.

```bash
bash <(curl -fsSL https://bureau.regionallyfamous.com/install)
```

The installer fetches the plugin through Omarchy’s normal Git validation, then installs and activates the matching plugin, theme, fonts, and branding in the same run. Running the quick-install command is consent to activate unsandboxed plugin code from the canonical repository.

Want to inspect it first?

```bash
curl -fsSL https://bureau.regionallyfamous.com/install
```

The complete manual install and trust model are documented in the [installation guide](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Installation-and-Trust).

## What you get

- **A real desktop.** Files and folders come from your configured Desktop directory. Select up to 64 items with Shift or Control, route them into folders or Trash, see the exact verb before release, and Undo unchanged regular-file moves from the receipt.
- **One shared Inspector.** Press Control+I on a desktop object, choose **Get Info** for a dock app, or press I on an overview window. Identity, facts, and actions stay in the same predictable places.
- **A bottom dock with a Window Ledger.** Launch apps, focus the most-recent surviving window, see 1/2/3+ window state, inspect current and other-workspace counts, open a titled window list, pin and reorder favorites, preview windows, and optionally auto-hide it.
- **A window overview and workspace board.** Move the pointer to the top-left corner or run `one-bit-bureau overview` to search and switch. The compact rail shows occupancy and moves the selected window to an existing ordinary workspace without closing the overview.
- **A complete visual system.** The Bitmap Workbench wallpaper, square paper-and-carbon surfaces, top-bar app context, notification styling, terminal palette, branding, and unlock art all belong together.
- **Thirty-two original app icons.** Every launcher-visible app in a fresh Omarchy Quattro install maps to an authored offline role, including office, creative, media, utility, communication, and web apps.
- **Sensible fallbacks.** An uncommon app keeps its recognizable native icon in grayscale. If that icon cannot be resolved, the dock uses an authored one-bit Application mark instead of leaving a blank. You can restore the original color icon at any time.
- **Two optional retro fonts.** Monaspace Krypton NF is the practical whole-desktop choice; Departure Mono is the sharper pixel-shaped alternative.
- **A reversible install.** One-Bit Bureau records what it owns, restores the settings and branding it replaced, and leaves your Desktop files and personal choices alone.

## Your first five minutes

| Try this | What happens |
|---|---|
| Single-click a desktop object | Selects it without opening it |
| Control-click or Shift-click objects | Builds a bounded multi-selection |
| Drag selected files onto a desktop folder | Shows the exact Move route, then a result receipt with Undo when reversal is provable |
| Press Control+I | Opens the selected desktop object's Inspector |
| Double-click it or press Return | Opens the selected file or folder |
| Choose Get Info on a dock icon | Opens application facts and actions; Show Windows opens its Window Ledger |
| Move to the top-left corner | Opens the searchable window overview |
| In Overview, use Control+Left/Right then Control+Shift+Enter | Chooses a workspace and moves the selected window there |
| Run `one-bit-bureau motion reduce` | Removes nonessential One-Bit Bureau motion |
| Run `one-bit-bureau font use krypton` | Selects the bundled Nerd Font-compatible retro font |

The [everyday-use guide](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Everyday-Use) covers keyboard controls, dock placement, optional app switching, fonts, motion, and icon management.

## See how it works

<table>
  <tr>
    <td colspan="2"><img src="docs/screenshots/runtime-apps.png" alt="A curated One-Bit Bureau workday with two local web desks, a Writer document, a grayscale three-file Files list, and five matching dock icons"><br><sub>A real-app workday staged as one composition: Web, Writer, Files, and no first-run debris</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/runtime-inspector-desktop.png" alt="The shared One-Bit Bureau Inspector showing identity, facts, and safe actions for a desktop object"><br><sub>One shared Inspector for desktop objects, applications, and windows</sub></td>
    <td width="50%"><img src="docs/screenshots/runtime-route-receipt-undo.png" alt="A One-Bit Bureau desktop receipt stating that two items moved to Projects and offering Undo"><br><sub>A local result receipt offers Undo only when reversal is proven</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/runtime-window-ledger.png" alt="The One-Bit Bureau Window Ledger listing two windows for one application on two workspaces"><br><sub>One app identity with a truthful titled-window ledger</sub></td>
    <td width="50%"><img src="docs/screenshots/runtime-workspace-board.png" alt="The One-Bit Bureau Overview after moving the selected window from Workspace 1 to Workspace 2"><br><sub>A stable workspace board that moves the exact selected window and stays open</sub></td>
  </tr>
</table>

These are real 1280×800 captures retained from passed disposable x86_64 Omarchy run `krlnvwgvq9`, using Omarchy commit `2c593dbb` and public runtime commit `bafae649`. That run produced 45 review frames and passed the exact public install, activate, update, remove, rollback, and user-data-preservation lifecycle. Its gallery also asserted exactly four intended application windows and exactly three authored Files artifacts before capture. This documentation revision only packages those unchanged evidence pixels and copy.

### The rest of the system

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/runtime-icon-picker.png" alt="One-Bit Bureau app icon picker with 32 original bitmap roles"><br><sub>Thirty-two offline icons cover every fresh-install app, with grayscale-native and one-bit Application fallbacks</sub></td>
    <td width="50%"><img src="docs/screenshots/runtime-overview.png" alt="One-Bit Bureau searchable window overview with ordinary workspaces 1 and 2"><br><sub>Searchable, keyboard-navigable windows and workspaces</sub></td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/screenshots/runtime-notification.png" alt="A One-Bit Bureau workday with a desktop-ready notification, Field Guide, grayscale Files list, top bar, dock, and wallpaper"><br><sub>The final workday state stays coherent across notifications, top bar, dock, applications, and wallpaper</sub></td>
  </tr>
</table>

## Make it yours

```bash
one-bit-bureau icon pack list
one-bit-bureau font list
one-bit-bureau font use krypton
one-bit-bureau motion reduce
one-bit-bureau motion full
```

The dock’s **Manage Icons** screen is the easiest way to use the automatic authored match, assign another One-Bit role, keep an uncommon app’s automatic grayscale-native fallback, restore an app’s original full-color icon, or choose your own local image. When no native icon can be resolved, the automatic mode uses the bundled one-bit Application mark instead of an empty box.

## Update or remove

```bash
one-bit-bureau update
one-bit-bureau remove
```

Removal restores the theme, top-bar position, transparency, and branding that One-Bit Bureau still owns. It keeps your Desktop files, dock pins, icon choices, custom icons, and saved positions.

## Honest limits

- This is an original Macintosh-inspired interface, not Apple artwork or a pixel-perfect copy of System 1.
- The dock is a useful modern launcher translated into the One-Bit Bureau style.
- Linux applications own their client-side title bars, so one plugin cannot make every app window identical.
- Wayland does not make a manual desktop-icon drag portable across separate layer-shell windows, so desktop-to-dock internal dragging is not advertised. Native external file drops and the desktop, Trash, and overview routes are supported.
- One-Bit Bureau keeps Omarchy’s tiling, launcher, Quick Look, notifications, controls, and normal `Super` navigation intact.
- Setup refuses to run beside enabled standalone desktop-icon, dock, overview, or active-window plugins that would duplicate the same surfaces.

## Help and technical details

The [Wiki](https://github.com/RegionallyFamous/one-bit-bureau/wiki) contains the detailed command reference, installation and trust model, app-icon rules, architecture, state files, theme and font provenance, development workflow, test gates, and troubleshooting.

- [Everyday use](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Everyday-Use)
- [Icons and app associations](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Icons-and-App-Associations)
- [Troubleshooting](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Troubleshooting)
- [Architecture and state](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Architecture-and-State)
- [Development and testing](https://github.com/RegionallyFamous/one-bit-bureau/wiki/Development-and-Testing)
- [Source-backed 1.2 research backlog](docs/ONE-BIT-BUREAU-1.2-RESEARCH-BACKLOG.md)

One-Bit Bureau is MIT-licensed. Imported-code and font notices are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
