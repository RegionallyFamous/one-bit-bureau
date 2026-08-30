# Bundled fonts

One-Bit Bureau includes two deliberately different monospace choices. Setup installs them into the current user’s font directory and refreshes fontconfig, but it does not rewrite terminal configs or change the user’s selected system font.

| File | Family reported by fontconfig | Version | License | Upstream | SHA-256 |
|---|---|---:|---|---|---|
| `MonaspaceKryptonNF-Regular-1.400.otf` | Monaspace Krypton NF | 1.400 | SIL Open Font License 1.1 | https://github.com/githubnext/monaspace | `e4f4ce9b02139544d20c46eaa0ae7df9cce7bfcdcdeb75bb70575236ccc86954` |
| `DepartureMono-1.500.otf` | Departure Mono | 1.500 | MIT | https://github.com/rektdeckard/departure-mono | `4d53f663155cf8bf7ffc8e688776e719625f7bbb80a8d90073438b249261a2e0` |

Monaspace Krypton NF is the practical whole-desktop choice because this build includes Nerd Font symbols used throughout Omarchy. Departure Mono is the more aggressively pixel-shaped display choice, but it does not include Omarchy’s Nerd Font glyph set and should not be selected as the global shell font unless the missing symbols are acceptable.

Exact upstream license texts are preserved under `fonts/licenses/`. The font binaries are unmodified files from the tagged upstream releases.
