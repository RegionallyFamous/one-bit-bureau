# One-Bit Bureau 1.2 research backlog

Research date: 2026-08-30

Status: product direction for the next release, not a promise that every item will ship unchanged.

## Decision

One-Bit Bureau 1.1 establishes the right model: select a visible noun, name the verb and destination, show the result near the action, and offer Undo only when reversal is provable. The next release should deepen that model at Linux desktop boundaries instead of adding more retro decoration.

The strongest research result is a four-part contract:

- Selection remains visible until the next meaningful state is ready.
- Every drag action has a non-drag pointer command and a keyboard path.
- Application identity, titled windows, and workspace destinations remain separate and legible.
- Filesystem and compositor actions are not reported as complete until their postconditions are observed.

This extends the primary-source findings in [the original Macintosh research](MACINTOSH-GUIDE-RESEARCH.md) and the implemented [desktop UI roadmap](DESKTOP-UI-RESEARCH.md). Apple’s current drag-and-drop guidance still emphasizes continuous feedback, multi-item drags, alternate commands, selection after a drop, and Undo when reliable. GNOME’s current desktop documentation validates a stable app-to-window-to-workspace hierarchy with both pointer and keyboard routes. [Apple drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop), [GNOME overview](https://help.gnome.org/gnome-help/shell-introduction.html), [GNOME workspace movement](https://help.gnome.org/gnome-help/shell-workspaces-movewindow.html)

## Ship first

### 1. Complete input equivalence

Audit every One-Bit Bureau drag route and guarantee three equivalent paths: direct drag, a single-pointer menu or button flow that does not require dragging, and a keyboard flow. The operation preview and final receipt must expose the same noun, verb, destination, and refusal reason on every path. This is the highest-priority product item because WCAG 2.2 provides a strong accessibility benchmark for web-authored drag interactions, while Apple recommends alternate commands when drag and drop is inconvenient or impossible. One-Bit Bureau uses that benchmark as product guidance for its native QML shell and does not claim formal WCAG conformance. [WCAG 2.2 Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html), [Apple drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop)

The acceptance suite must exercise pointer-only and keyboard-only routing, focus return, reduced motion, an invalid target, a partial result, and an expiring receipt. State may not rely on color alone. Important results must be represented through accessible names or status semantics, not only painted text.

### 2. Harden the operation engine at filesystem boundaries

Keep internal Desktop-to-folder moves atomic and no-overwrite. Add explicit cross-filesystem verification before offering Undo. Continue delegating Trash to Gio and do not offer Trash Undo until the exact FreeDesktop .trashinfo record and recovery path are known. The Trash specification requires unique stored names and treats the metadata record—not the stored filename—as the authority for restoration. [FreeDesktop Trash specification](https://specifications.freedesktop.org/trash/latest/)

Treat external file drops as Copy until interoperability testing proves that a source and target correctly negotiated Move. A target that independently moves a file after the source also honors a Move action can double-apply the operation. Add sandbox-aware file transfer through the XDG File Transfer portal for peers and toolkits that advertise and retrieve `application/vnd.portal.filetransfer`; retain a tested local `text/uri-list` path or explicitly refuse the drop otherwise. A receiver cannot unilaterally make an arbitrary peer portal-aware. [XDG File Transfer portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileTransfer.html)

For actions with a defined observable postcondition, verify it within a bounded timeout. When no reliable postcondition exists, the receipt must describe the request—such as **Launch requested** or **Close requested**—and never claim completion. A successful dispatcher exit is only a request; the receipt should describe what the system actually observed.

### 3. Make application identity deterministic

Build one documented resolver from an observed Wayland `app_id` or XWayland class to one desktop entry, preferring an exact desktop-file ID, then declared `StartupWMClass`, then bounded aliases, with weaker process heuristics only as a last resort. Keep one dock identity per application, but never collapse its titled windows or workspace locations. The FreeDesktop desktop-entry standard defines desktop-file identity, icon lookup, and StartupWMClass; xdg-shell says `app_id` identifies the general application class and should match the desktop-file basename; the icon-theme standard defines the shared lookup contract. [Desktop Entry specification](https://specifications.freedesktop.org/desktop-entry/latest-single/), [xdg-shell app_id](https://wayland.app/protocols/xdg-shell#xdg_toplevel:request:set_app_id), [Icon Theme specification](https://specifications.freedesktop.org/icon-theme/latest/index.html)

Add an interoperability fixture matrix for native Wayland, XWayland, Electron, GTK, Qt, Flatpak, and applications that change title or class after launch. A focus or close action must re-resolve its address immediately before dispatch and verify the resulting client state.

### 4. Define multi-monitor desktop ownership

One filesystem noun must have one spatial owner. Multiple monitors must not show duplicate movable copies of the same Desktop item or race while saving its position. Store one ownership record per noun, such as `{output, x, y}`, use the primary output as the default owner, and define deterministic migration on hotplug or output removal before enabling more cross-monitor spatial behavior.

The desktop must also honor the configured XDG Desktop directory and remain disabled when that setting resolves to the home directory, because XDG user directories use the home path to represent a disabled well-known directory. [xdg-user-dirs](https://wiki.freedesktop.org/www/Software/xdg-user-dirs/)

### 5. Make workspace scope explicit

The Workspace Board should continue to show existing ordinary Hyprland workspaces, occupancy, and the exact selected window. Define whether its scope is the current monitor or all monitors and say so in the Inspector and accessible description. Add named-workspace and multi-monitor research before accepting destinations beyond bounded ordinary numeric workspaces.

Use current Hyprland Lua dispatchers first and keep legacy command dispatchers only as compatibility fallbacks. Current Hyprland documents `hl.dsp.focus` with a workspace argument and `hl.dsp.window.move` with workspace, follow, and window arguments, but also warns that the dispatcher table is not guaranteed to remain stable. Pin the Omarchy-supported Hyprland version in the release guest or capability-detect the current form, and exercise the legacy fallback. Postcondition checks remain required because dispatch is asynchronous. [Hyprland dispatchers](https://wiki.hypr.land/Configuring/Basics/Dispatchers/)

## Prove before shipping

### Spring-loaded folders

Apple’s model keeps the drag session alive while a destination opens. A layer-shell desktop that launches an external file-manager window after a hover is not equivalent: the drag cannot reliably continue across the new surface. Retain the current same-surface folder route, but do not expand or market cross-window spring loading until a prototype preserves the active drag, cancellation, focus, and keyboard parity. If that cannot be done, replace it with an explicit **Open Folder** command while the move remains pending, or remove the behavior.

### External Move and application drops

Test Nautilus, Dolphin, Thunar, GTK, Qt, Electron, native Wayland, XWayland, and Flatpak sources and destinations. Promote external Move only for negotiated pairs that pass success, refusal, cancel, collision, source disappearance, and cross-filesystem cases. Application drops must advertise standards-based MIME types and use portal file transfer where required.

### Trash Undo

Do not infer a trashed object’s identity from its displayed or stored filename. Ship Undo only when the exact .trashinfo record, original path, collision policy, and post-restart recovery are recorded and verified. Until then, the receipt should truthfully say **Moved to Trash** without an Undo button.

### Layer-shell focus policy

Interactive One-Bit Bureau surfaces should use on-demand keyboard focus and release it predictably. Exclusive focus is appropriate for lock screens and password prompts, not ordinary panels. The layer-shell protocol explicitly describes on-demand focus as the mode for keyboard-usable desktop shell components. [wlr layer-shell protocol](https://wayland.app/protocols/wlr-layer-shell-unstable-v1)

## Deliberately defer

- Cross-layer-shell dragging from desktop icons into the dock. The Wayland boundary is real, and a menu action is more trustworthy than a simulated drag that can lose ownership.
- A fake universal application menu or universal window chrome. Linux clients do not expose one complete, stable action or decoration API.
- Arbitrary live desktop widgets. They weaken the object model and add lifecycle ambiguity.
- Workspace creation as a side effect of a drop. First prove moves among visible existing destinations.
- Permanent operation history presented as guaranteed Undo. Keep private journals for validation and recovery, but expose Undo only for the latest still-provable operation.

## Release gates

1. A single interaction map lists every drag action beside its pointer and keyboard equivalents.
2. Unit tests cover collisions, symlinks, stale paths, cross-filesystem copies, partial batches, malformed portal data, stale window addresses, and vanished workspaces.
3. A disposable Omarchy VM proves native Wayland, XWayland, Flatpak, two monitors, fractional scaling, hotplug, reduced motion, and plugin reload during an operation.
4. The app-identity matrix passes GTK, Qt, Electron, terminal, browser, and multi-window cases without duplicate dock launches.
5. The DnD matrix proves Copy, refusal, cancellation, and sandboxed transfer before any external Move is enabled.
6. Each compositor and filesystem mutation with a defined observable postcondition verifies that result before painting a success receipt; otherwise the receipt truthfully reports that a request was sent.
7. Documentation and screenshots describe the same tested behavior and identify any remaining Wayland limit plainly.

## Recommended 1.2 cut

The smallest release worth calling 1.2 is input equivalence, deterministic app identity, verified postconditions where observable, conditionally portal-aware external Copy, and explicit multi-monitor ownership. Spring-loaded cross-window dragging, external Move, and Trash Undo stay behind proof gates. That cut makes One-Bit Bureau feel more Macintosh-like in the important sense—stable, forgiving, and legible—while becoming a better Linux citizen.
