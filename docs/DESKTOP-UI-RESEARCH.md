# Desktop UI Research and Improvement Roadmap

Research date: 2026-08-30

Status: implemented in One-Bit Bureau 1.1.0, with the explicit cross-window Wayland limit recorded below.

## Implementation result

The roadmap shipped as one interaction system rather than four disconnected widgets:

- The shared Inspector handles desktop objects, dock apps, and overview windows with one bounded Identity/Facts/Actions model.
- Desktop routing supports bounded multi-selection, desktop folders, Trash, local external drops, named verbs, receipts, partial/error states, and Undo only for unchanged hash-proven regular-file moves.
- The dock keeps one app identity and exposes truthful count, active, current-workspace, other-workspace, most-recent-window, and explicit window-list state.
- The overview workspace board shows stable ordinary-workspace occupancy and moves the selected window through a validated address-and-workspace helper while remaining open.

One proposed route did not pass the platform gate: an internal manual desktop-icon drag cannot reliably become a native drop inside a separate Wayland dock `PanelWindow`. One-Bit Bureau therefore supports native external file drops and its proven same-surface routes without claiming desktop-to-dock dragging.

## Research question

What should One-Bit Bureau learn from influential desktop operating systems if the goal is a better daily desktop rather than a visual imitation of one historical machine?

The answer is not more period decoration. The strongest systems make three things unusually clear:

1. What object the user is acting on.
2. What an action will do before it happens and how to recover afterward.
3. Where applications and windows are, even when they are not currently visible.

One-Bit Bureau already has the right foundation: real Desktop files, select-before-open behavior, persistent positions, a safe launcher trust boundary, a dock, app and window previews, a searchable overview, keyboard paths, accessible labels, grayscale fallbacks, and reduced motion. Its interaction depth now trails its visual finish in three places: object information, drag meaning and recovery, and resting dock state.

## Evidence brief

| System | Method worth adapting | What to leave behind |
|---|---|---|
| Xerox Star | Select a visible object, then use a small set of consistent verbs such as Move, Copy, Delete, Show Properties, and Undo. Inspect the selected noun in a property sheet. [Designing the Star User Interface](https://www.bitsavers.org/pdf/xerox/sdd/OSD-R8203_Xerox_Office_Systems_Technology_Nov82.pdf) | Literal office-machine metaphors, dedicated command keys, and assumptions from a closed workstation. |
| Classic Macintosh | Immediate selection feedback, perceived stability, dimmed unavailable commands, safe defaults, and forgiveness make the interface learnable without constantly changing its shape. [The Apple Desktop Interface](https://raw.githubusercontent.com/gingerbeardman/apple-human-interface-guidelines/main/1987%20Apple%20Human%20Interface%20Guidelines%20-%20The%20Apple%20Desktop%20Interface.pdf) | One-button-mouse dependence and Apple-owned icons, typography, sounds, window chrome, and trade dress. |
| NeXTSTEP | A persistent dock can distinguish stored launchers from running applications, communicate startup state, preserve user arrangement, and expose a stable command inventory with keyboard alternatives. [NeXTSTEP User Interface Guidelines](https://www.bitsavers.org/pdf/next/Release_3_Nov93/NeXTSTEP_User_Interface_Guidelines_Release_3_Nov93.pdf) | The black Dock, app tiles, tear-off menus, and other recognizable NeXT surface signatures. |
| RISC OS | Treat destinations as verbs: dropping a file on an editor opens it, on a document inserts it, and on a printer prints it. A save object can travel directly to its destination. [RISC OS Style Guide](https://www.riscosopen.org/zipfiles/platform/common/StyleGuide.3.pdf) | Three-button Select/Menu/Adjust dependence and drag-only workflows that hide actions from keyboard and assistive-technology users. |
| Windows | Keep a persistent representation of running work and make object-specific properties available from the selected file or window. Modern taskbar previews also make multiple windows explicit. [Microsoft taskbar documentation](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar) | A single strip that tries to contain every launcher, window, status source, and system control until it becomes cluttered. |
| BeOS and Haiku | Group windows beneath one application identity, distinguish minimized and off-workspace windows, expose file metadata, and show independent progress for file transactions. [Haiku Deskbar guide](https://i18n.haiku-os.org/userguide/data/export/docs/userguide/en/deskbar.html), [Haiku Tracker guide](https://i18n.haiku-os.org/userguide/data/export/docs/userguide/en/tracker.html) | Replicants and arbitrary live desktop widgets, which add lifecycle fragility and visual noise without strengthening the core object model. |
| GNOME | Join live windows, workspaces, and type-to-search in one overview while retaining non-search navigation for people who do not search. [GNOME desktop overview](https://help.gnome.org/gnome-help/shell-introduction.html), [GNOME search guidance](https://developer.gnome.org/hig/patterns/nav/search.html) | Replacing persistent desktop objects with a full-screen launcher. That conflicts with One-Bit Bureau's premise and duplicates Omarchy's launcher. |
| KDE Plasma | Keep the common workflow obvious, make expert accelerators additive, provide keyboard and pointer parity, show meaningful drag previews, and communicate failures with a next action. [Simple by default](https://develop.kde.org/hig/simple_by_default/), [Powerful when needed](https://develop.kde.org/hig/powerful_when_needed/), [Accessibility](https://develop.kde.org/hig/accessibility/), [Status changes](https://develop.kde.org/hig/status_changes/) | Settings sprawl. Customization is not a substitute for choosing a coherent default behavior. |
| Current macOS | Give selected objects a real Get Info view; predict drag results; support multi-item dragging, spring loading where justified, alternate non-drag commands, and Undo when reversal is reliable. [Get Info](https://support.apple.com/en-au/guide/mac-help/mchlp1774/mac), [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop), [Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) | A fake universal app menu, Dock magnification, Aqua behavior, and Apple icon silhouettes. Those would imitate a surface without reproducing the platform integration that makes it work. |

## Pre-1.1 product gaps

The source audit found four concrete gaps rather than a need for another visual overhaul.

- The dock menu labels its icon-picker action **Get Info**, but it opens icon selection directly. Desktop objects have no corresponding information surface. This is a semantic mismatch, not merely a missing feature.
- The desktop accepts external files on the desktop or Trash, but folders and dock applications are not meaningful drop targets. Current drag feedback is a generic border and does not predict the operation.
- A dock item has one binary running mark whether it owns one window or eight. The preview system already knows the individual windows, but the resting dock does not expose count, active state, or another-workspace state.
- The overview can filter by workspace but does not present workspaces as destinations for moving a selected window.

## Direction contract

One-Bit Bureau should become a routing desk, not a retro OS museum.

> Every object has an index card. Every drag names its verb. Every application keeps a legible window ledger.

The existing **Bitmap Workbench: select the noun, act second** direction remains valid. The next releases should complete the loop:

```text
visible noun -> explicit verb -> visible result -> reliable recovery
```

The original visual vocabulary should remain abstract rather than historical: stable bitmap plates for information, a compact `noun -> verb -> destination` equation for pending operations, a local completion plate for results, and restrained nested-corner marks for window counts. “Routing slip,” “receipt,” and “ledger” are internal design concepts, not an excuse for faux paper, tabs, stamps, clipboards, or filing-cabinet decoration.

## Original feasibility gate

| Territory | Verdict | Smallest credible release |
|---|---|---|
| Bureau Inspector | Prototype first | Read-only facts for a selected desktop item, dock app, or window; existing safe actions only after targets are re-resolved at activation time |
| Window Ledger | Go, narrowly | Grouped running-window list, active state, explicit Activate and Close, truthful accessible descriptions, and no new live previews required for correctness |
| Verb-aware routing and Undo | Defer until helper proof | A local-only operation helper that reports completed or failed outcomes; no Undo promise in the first proof |
| Overview workspace board | Defer | Revisit after the Ledger proves monitor scope, stale-state handling, and lifecycle behavior |

## Roadmap

### 1. Bureau Inspector

Ship this first. It repairs an existing semantic mismatch and creates the shared object model needed by later work.

One temporary inspector should serve four nouns: a desktop file or folder, a launcher, a dock application, and an overview window. Stable rows remain in place and dim when unavailable.

The first release should be deliberately narrow and mostly read-only:

- Files and folders: name, kind, location, size, modified time, preview policy, and launcher trust when applicable.
- Applications: app name, desktop ID, icon association mode and source, pinned state, running state, window count, and workspaces.
- Windows: application owner, title, workspace, monitor, active state, and address only when useful for diagnostics.
- Actions: Open, Show in Files, Change Icon, and the existing safe launcher actions. Rename, Open With, permission changes, and general preferences are deferred.

Implementation shape:

- Own one reusable `InspectorPanel.qml` at the experience level so the desktop and dock do not create competing overlays.
- Query file metadata through one bounded helper that returns validated JSON. Do not synchronously inspect arbitrary content inside QML delegates and do not read remote URIs.
- Reuse the existing icon state helper and dock window resolver.
- On disappearance or permission failure, keep the card open, state what changed in plain language, and dim only the unavailable actions.
- Restore focus to the invoking desktop object or dock item on dismissal. Support Escape, logical keyboard traversal, practical pointer targets, and accessible names for every action.

Risk: medium. Smallest useful release: read-only data plus the safe actions that already exist.

### 2. Window Ledger

Ship this next. It makes the dock truthful without turning it into a second overview.

The dock keeps one stable identity per application and adds a restrained state vocabulary. The Ledger is the app-and-window form of the shared Inspector architecture, not another dashboard or popup species:

- One, two, or three-plus nested-corner marks for window count.
- A distinct active-app mark that does not rely on color.
- A visible distinction between windows on the current workspace and windows only on other workspaces.
- An accessible description such as “3 windows, active, pinned.”
- A stable dock menu section listing windows by title and workspace, with explicit focus and close actions.

Primary click should continue to focus the most-recently-used surviving window. Multiple windows must never silently resolve to an arbitrary candidate, and a temporarily stale compositor address must not cause the plugin to launch a duplicate application. The existing preview panel remains the visual chooser.

Implementation can reuse the window gathering already used by previews, record per-app most-recently-used window addresses from active-toplevel changes, and send validated addresses through the existing no-pointer-warp focus helper.

Risk: low to medium. Smallest useful release: count, active state, deterministic most-recently-used focus, and a truthful accessible description.

### 3. Verb-Aware Routing and Receipts

This is the largest interaction improvement and the highest-risk work. Build it only after a dedicated filesystem and Wayland feasibility pass.

The intended routes are:

| Source | Destination | Predicted verb |
|---|---|---|
| Desktop item | Desktop folder | Move or Copy to Folder |
| External local item | Desktop or Desktop folder | Copy to Desktop or Folder |
| Local file | Compatible dock application | Open With Application |
| Desktop item | Trash | Move to Trash |
| Any unsupported combination | Invalid target | Cannot accept, with a short reason |

During a drag, one target inverts and a one-bit routing slip names the pending result, for example “Move 3 items to Projects” or “Open report.pdf with GIMP.” Escape cancels. Every route also appears as a context-menu or keyboard action; dragging is an accelerator, never the only path.

A structured operation controller should replace fire-and-forget mutation calls. It should accept bounded arrays of validated local paths or URIs as separated arguments and return bounded JSON containing an operation identifier, verb, sources, destination, and result. It must handle vanished paths, symlinks, collisions, cross-filesystem copies, partial batches, read-only targets, helper failure, plugin reload, reduced motion, and multiple monitors.

Completion plates should be local to the action rather than ordinary background notifications:

- “Moved 3 items to Projects · Undo” when reversal is provable.
- “Opened report.pdf with GIMP” without a false Undo promise.
- “2 of 3 items moved · Review” for a partial result.

Undo begins with operations whose before-and-after state One-Bit Bureau fully owns: dock unpin and reorder, desktop position changes, and collision-free file moves with a durable operation journal. Do not promise arbitrary Trash restoration until XDG Trash identity, collision handling, and recovery after plugin restart are transactionally verified.

Multi-selection is a prerequisite. Replace the single global desktop selection with a bounded selection set, add Shift and Control selection, retain the selection after a successful move, and provide keyboard parity. A marquee is optional and should not ship until it has an equivalent non-pointer path.

Risk: high. Smallest useful release: multi-selection, Desktop item to Desktop folder, exact verb feedback, menu parity, and receipts. Dock application drops and spring-loaded folders come later.

## Follow-on: workspace board

After the three core territories are stable, the overview can gain a compact workspace rail with stable ordering and occupancy. A window card can move to an existing ordinary workspace by drag or by a named keyboard or context action. The destination states “Move Foot to Workspace 3,” the card visibly re-homes after success, and the overview stays open.

This should remain a window-routing tool. It must not grow into another app launcher, a second dock, or a general dashboard. Named and numeric workspaces, pinned and special workspaces, workspace removal during a move, and multi-monitor rules need explicit acceptance coverage.

## Explicit deferrals and rejections

- No fake global application menu. Arbitrary Linux clients do not expose one stable action API.
- No BeOS-style arbitrary replicants or permanent live desktop widgets. They weaken visual calm and add fragile service lifecycles.
- No clipboard history, screenshot courier, or previous-workspace feature. Omarchy already owns those workflows.
- No additional hot corners or edge bands. The overview and dock already own the useful edges.
- No spring-loaded folders before deterministic folder drops, cancellation, and keyboard parity are proven.
- No exact Apple, NeXT, RISC OS, Windows, BeOS, or Amiga chrome, icons, sounds, type, or menu geometry.
- No retro startup chime, CRT effects, scanlines, beige-device costume, or animation added only to evoke a period.
- No broad settings page for every new behavior. Choose strong defaults and expose only settings tied to real access or workflow needs.

## Verification gates

Each phase must be tested as an interaction system, not accepted from a still screenshot.

- Unit-test every pure model and bounded helper, including malformed JSON, missing items, collisions, stale addresses, and partial operations.
- Add source-contract tests for accessible names, keyboard paths, stable disabled rows, focus return, and reduced-motion behavior.
- In the VM, test pointer-only and keyboard-only paths, long names, empty and crowded desktops, one and many app windows, off-workspace windows, app closure during a menu, helper failure, two monitors, fractional scaling, and plugin reload mid-operation.
- For drag work, verify source, target, predicted verb, refusal reason, success, partial failure, cancellation, and any promised recovery as separate states.
- Define desktop object ownership on multiple monitors before extending spatial behavior. The current shared item model and global selection can otherwise present one filesystem noun in more than one place.
- Keep ordinary Omarchy navigation, Alt+Tab, launcher, clipboard, capture, lock, and top-bar behavior reachable while the new surfaces have focus.

## Recommended delivery order

1. Genuine read-only Bureau Inspector and correction of the current Get Info label/action mismatch.
2. Truthful dock window count, active state, window list, and deterministic most-recently-used focus.
3. Bounded desktop multi-selection and desktop-folder routing with explicit verb feedback.
4. Structured receipts and only narrowly provable Undo.
5. Overview workspace board.
6. Compatible dock-application drops and, only after cancellation behavior is proven, spring-loaded folders.

This order produces visible improvements early while isolating filesystem, compositor, and cross-surface drag risk.
