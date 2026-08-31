# Application identity and window actions

One-Bit Bureau assigns each running window to one dock identity with one deterministic resolver. Window titles are mutable content and never participate in identity.

## Resolver priority

The resolver stops at the first uniquely owned value in this order:

1. Exact desktop-file ID or native Wayland `app_id` after removing only a trailing `.desktop` suffix.
2. Exact `StartupWMClass`, including XWayland class values and stable `initialClass` values.
3. A unique bounded alias: desktop metadata aliases, the canonical desktop ID, the final canonical ID segment, or the narrowly recognized Chromium app-mode class `chrome-<host-or-id>__<path>-<profile>`.
4. A unique process or executable basename from the live window PID and the desktop entry `Exec` field. Flatpak and Snap launcher targets are extracted without executing the entry.

Every non-exact tier has one-owner semantics. If two desktop entries own the same alias, `StartupWMClass`, or executable, that tier returns an explicit ambiguous result and does not merge the applications. A generic mutable class may be skipped when a later stable `initialClass` value has one owner. Unknown applications can retain a bounded unresolved class/app ID for a temporary dock identity, but they are never joined by equal title text.

## Input ceilings

The pure resolver accepts at most 4,096 desktop entries, 12 values per live identity field group, 16 aliases per entry, and 12 process names per entry. IDs, classes, and process values are at most 160 characters; desktop `Exec` text is at most 512 characters. The metadata bridge scans at most 8,192 desktop files, reads at most 256 KiB from any one desktop file, returns at most 1 MiB, and reads process metadata for at most 64 address/PID pairs. Values beyond a ceiling are rejected, not truncated into a possible match.

The plugin-local metadata bridge reads the XDG desktop entry directories and bounded `/proc` records because the supported Quickshell `DesktopEntry` surface does not expose `StartupWMClass`. It does not execute desktop-file content and does not modify Omarchy or Hyprland.

## Window action truth

Focus and close re-resolve the current foreign-toplevel membership, Hyprland address, and canonical app identity immediately before dispatch. Address reuse by another app is treated as a stale target. A stale focus target advances through the app's bounded MRU candidates and never falls back to launching another process. New Window is an explicit action; ordinary dock activation checks both the previous authoritative running snapshot and the current snapshot before considering a launch.

Every focus, close, open, and new-window request publishes `lastActionStatus` and `actionStatusReported(status)`. Stable states are `requested`, `observed`, and `failed`; `idle` is used before the first action. `observed` means a bounded postcondition was seen in the supported QML window models. If the postcondition is not seen within 1.4 seconds, the state remains `requested` with an unconfirmed message; it is never mislabeled completed.

`DockPanel` exposes the canonical `windowLedger`, `lastActionStatus`, `actionStatusReported(status)`, `inspectorRequested(context, invokingScreen, invokingPosition)`, `inspectorContextForApp(appId)`, and `performInspectorAction(actionId, context)` contracts. The dock IPC additionally exposes `getIdentityForAddress`, the last-action getters, and explicit focus, close, and new-window request methods for deterministic acceptance tests.
