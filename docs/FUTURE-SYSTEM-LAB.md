# One-Bit Bureau future system lab

Research date: 2026-08-31

Status: ranked prototype territory after 1.2, not shipped behavior.

## Product thesis

One-Bit Bureau should push the desktop by making files, windows, applications, devices, displays, and sessions behave like stable objects with legible state. It should not replace the operating system beneath them.

Every experiment remains one third-party plugin inside Omarchy's single Quickshell process. It uses only its own service, panels, overlays, IPC targets, bounded local helpers, documented Omarchy commands/IPC, and public Quickshell models. It does not start another ShellRoot, replace Omarchy services, depend on private `shell` object properties, or rewrite Hyprland's base configuration or monitor layout.

A coordinated mode records only the state it changed, its original values, stable identities, and observed postconditions in a private, atomically written journal. On normal exit it may restore only values it still owns. After a crash, recovery re-resolves identities and reports a recoverable or abandoned session; it never blindly restores compositor, audio, DND, idle, or power state. No experiment earns release by guessing that a dispatcher request worked.

## What the current stack can safely expose

| System territory | Useful native surface | Boundary to preserve |
|---|---|---|
| Plugin host | Combined service, panel, and bar-widget entry points with one shared service instance | Entry points remain ordinary Items; never start another ShellRoot |
| Windows and workspaces | Quickshell Hyprland models, Wayland toplevels, monitor events, and current Omarchy/Hyprland dispatchers | Re-resolve identity before mutation and observe the result afterward |
| Shell surfaces | Per-monitor layer-shell panels with deliberate masks and on-demand keyboard focus | Do not pretend an internal drag can continue reliably across separate Wayland surfaces |
| Window imagery | Bounded ScreencopyView previews for visible, eligible Wayland toplevels | Treat capture as sensitive and GPU-expensive; stop it immediately when hidden; XWayland, protected, and unavailable surfaces need an honest no-preview state |
| Applications | Desktop entries, One-Bit Bureau's deterministic identity resolver, dock identities, and Window Ledger | Do not depend on undocumented host-private application-library state |
| Notifications and OSD | Stock Omarchy notification command and public notification/OSD IPC | Never start a competing notification daemon or scrape private notification state |
| Audio and media | Quickshell PipeWire and MPRIS models plus stock Omarchy audio commands | PipeWire's default-sink API is global, not proof of a safe exact-app route; per-stream routing remains a prototype until an identity-safe helper can observe and restore the exact stream without affecting unrelated audio |
| Idle, lock, and power | IdleMonitor, UPower, Hyprland events, and stock Omarchy session commands | Use documented commands and public state; do not bind to private lock-service objects |
| Network, Bluetooth, and displays | NetworkManager, Bluetooth, UPower, monitor events, and public Omarchy commands | Device identities can disappear or change; every action needs local degradation |
| Clipboard and capture | Clipboard MIME inspection and Omarchy's screenshot, OCR, and recording pipeline | Handle clipboard data as private and never replace the existing capture backend |
| Theme and background | Native theme activation, semantic tokens, wallpaper state, and background transition IPC | Do not add a competing wallpaper daemon or per-workspace background owner |
| Keyboard chords | An optional plugin-owned Hyprland include after exact-version testing | Explicitly install and remove it, namespace every binding, preserve user bindings, require Escape and timeout recovery, and never rely on the global-shortcuts portal as an unconditional fallback |

Architecture references: [Omarchy shell contract](https://github.com/basecamp/omarchy/blob/master/docs/omarchy-shell.md), [Hyprland dispatchers](https://wiki.hypr.land/Configuring/Dispatchers/), [Quickshell Hyprland API](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/), and [wlr layer-shell](https://wayland.app/protocols/wlr-layer-shell-unstable-v1).

## Build first after 1.2

### Light Table

Marquee-select images or videos, choose **Review on Light Table**, and turn those real desktop objects into a fullscreen contact sheet with A/B comparison. Passive desktop previews stay grayscale; deliberate review may show the originals in color. The first slice is read-only JPEG/PNG review with bounded decoding. Exported picks delegate to the existing verified Copy operation and no ratings, metadata, or sidecars are written implicitly.

Why it belongs: it is the clearest extension of the current desktop object model, has a contained recovery story, and creates a striking demonstration without becoming a generic media viewer.

### Folded Rooms

Choose **Fold Room** on a Workspace Board tile and create a local `.bureau-room` desktop object that records a bounded list of application identities. Opening it previews the plan, launches missing apps, and moves only newly or uniquely observed windows onto one selected existing workspace. The first slice promises **Observed windows arranged**, never application state, document, or session restoration.

Why it belongs: it connects desktop objects, app identity, the dock, and workspaces in a way that only a shell-native plugin can.

### Scan Desk

Treat a connected scanner as equipment: preview a scan, show a temporary preview that has not been saved, then explicitly **Save to Desktop** as one verified object. SANE remains an optional user-installed capability. Device output is always data, temporary files remain bounded, and a disconnect must leave either a verified final file or an honestly labelled recovery file.

Why it belongs: it turns a physical device into the same noun–verb–receipt model and occupies territory not already crowded by generic scanner dashboards.

## Prototype next

### Cinema Handoff

Choose a local video or exact MPRIS player and **Watch on Projector**. First move and verify that exact client on an existing output. Fullscreen, DND, idle, and audio remain separately confirmed prototype steps with separate receipts. Exact-app audio routing does not ship until a helper can prove and restore one stream without changing unrelated audio. It never rewrites monitor geometry or kills the player.

### Print Proof

Supported PDF files become a proof sheet naming the selected printer, printer-reported media and duplex/color capabilities, page count, scale, and file order. Printing requires explicit confirmation. The receipt follows the real CUPS job ID and offers Cancel only while CUPS reports that the job remains cancelable.

### Reading Rail

Open a keyboard-controlled reading aperture over the focused output. It dims surrounding content, moves by small configurable screen-relative steps, supports reduced motion, and closes through Escape or IPC. It does not inspect application content, alter app scaling, capture pixels, or claim to replace a screen reader.

### Quiet Landing

Shift-click a pinned app to **Open Next Door** on one selected existing workspace without abandoning the current task. The dock shows a pending destination and reports arrival only after observing one unambiguous new toplevel. If the app reuses an old window, spawns an ambiguous helper, or steals focus before placement, the feature abandons placement rather than moving the wrong window.

### Display Coat Check

Remember the exact window assignments for a connected display through event-driven state during the current session. On removal, report how many surviving windows were checked in. Offer restoration only when make/model/serial or EDID establishes the returning output's identity and every exact address, PID, workspace, and destination still resolves. Connector names such as `DP-1` are not identity, and restoration never crosses a shell/session restart.

## Small, high-value experiments

- **Return Ticket:** after One-Bit Bureau initiates a jump to an off-workspace or off-monitor window, expose one memory-only, 30-second route back to the exact prior address, workspace, and monitor.
- **Fresh Capture on the Desk:** run the stock Omarchy screenshot command in save mode, validate the returned local path with `lstat`, and offer an explicit verified Copy to Desktop; do not create a fake desktop object, watch a directory, or replace capture.
- **Mic Left Behind:** when an exact PipeWire-to-application match remains live off-workspace, label the responsible dock app and its workspace; unknown ownership stays unknown.
- **Bring Sound Here:** keep this prototype-only until an optional helper proves one exact stream's identity, prior target, observed move, and ownership-safe rollback; never use the global preferred sink as if it were an app route or make audio follow focus silently.
- **Take Slate:** defer exact-target recording until Omarchy exposes a public verified toplevel/output recorder boundary. The credible current slice opens the stock recording flow and offers the returned, validated clip after it exits.
- **Noun Chord:** an optional, exactly owned Hyprland submap shows only valid commands for the current desktop object or window, exits after one action, and always has Escape plus a three-second timeout.

## Labs, not promises

- **Play Session:** coordinate one exact game identity, an existing workspace/output, fullscreen, DND, idle, and an available Omarchy power profile while restoring only still-owned state.
- **Remote Desk Passport:** represent a user-selected SSH config alias as a desktop object without reading private keys, storing credentials or expanded host details, bypassing host verification, or inventing startup commands.
- **Stage Sheet:** preflight an exact presentation window and report window movement, DND, and recording requests separately; it must never imply universal redaction or external capture control.

## Keep rejected

- A universal file-to-app drag conveyor across separate Wayland surfaces.
- A second notification daemon or private-notification-history scraper.
- Automatic per-workspace wallpaper ownership.
- Universal app chrome or a fake global application menu.
- Arbitrary live desktop widgets, user-authored shell hooks, automatic package installation, or permanent compositor rewrites.
- Claims of session restoration, successful launch, successful close, successful move, or completed capture before the corresponding state is observed.

## Release order

Finish 1.2's input equivalence, deterministic identity, multi-monitor ownership, postcondition checks, diagnostics, and truthful optional GTK3 preview first. Before any prototype mutates a window or display, build one shared window-action adapter that preflights address, PID, workspace, and monitor; dispatches through argv-only helpers; observes a bounded postcondition; and returns only confirmed, pending, or not performed. Then build Light Table as the first flagship lab, prototype Folded Rooms and Scan Desk, and use Cinema Handoff as a later whole-stack state-ownership stress test.

No new lab may add continuous hidden polling for windows, displays, PipeWire, or CUPS. Use public event-driven models while a surface or owned session is active, or invoke a bounded helper from an explicit user action.
