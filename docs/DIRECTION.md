# Paper Jam ’84 direction contract

## Product sentence

Paper Jam ’84 turns Omarchy into a Bitmap Workbench: select the noun, act second, and move expressive one-bit objects across an illustrated electronic worktable while modern applications remain recognizable and usable.

## Thesis

This edition applies the original Macintosh interface method rather than reproducing its owned appearance. Objects keep stable positions, commands act on a visible selection, feedback is immediate, unavailable actions stay discoverable, and focus changes the smallest meaningful region instead of repainting the whole screen.

## Research-derived laws

1. **Object before action.** A single click selects a desktop object, a double-click opens it, Return opens the selected object, and an empty desktop click clears selection.
2. **Visible ownership.** Selection inverts a compact name or control rail. Object artwork, including picture-file icons, reverses with its rail.
3. **Perceived stability.** Objects keep their positions, menu inventories do not jump when an action becomes unavailable, and overview preview bodies do not change value when focus moves.
4. **Immediate feedback.** Hover, drag targets, selection, focus, disabled state, and risky actions have distinct visible treatments without depending on hue.
5. **Forgiveness.** Risky launcher confirmation makes Cancel the double-outlined safe default. Enter and Escape cancel; neither key trusts nor executes a launcher.
6. **Consistency over cleverness.** The same paper, carbon, muted neutral, single rule, double rule, and ownership inversion mean the same things across desktop objects, menus, the launch shelf, overview, and top rail.
7. **Black-and-white first.** Shell hierarchy remains complete in grayscale. Terminal and application semantic colors survive as restrained modern exceptions.

## Surface system

- The desktop ground is an original ImageGen-authored one-bit machine workbench: paper stacks, organizing trays, cables, toothed leaves, and abstract mechanisms frame a calm central work field. The leftmost object lane and bottom-center shelf zone remain deliberately quiet.
- Paper windows, dialogs, menus, notifications, and the top rail sit clearly above the desktop ground. All shell surfaces are opaque, square, and integer-aligned.
- Generic folder, document, picture-file, archive, link, launcher-fallback, and Trash objects use expressive raster mini-illustrations reduced from original ImageGen sources. Recognizable application icons remain preserved rather than thresholded.
- The overview is a contact sheet of stable paper preview bodies. Keyboard selection inverts only the title rail; the actually active window receives a double outer rule.
- The top rail names the active application first. A distinct window or document title is secondary context, never a fake global menu.
- The dock remains a modern Paper Jam launch shelf translated into this bitmap workbench system. It is not presented as historical Macintosh behavior.
- Hyprland windows use square two-pixel borders with no blur, shadow, rounding, or opacity effects.

## Palette and typography

Application and dialog paper is `#f4f4f0`, carbon is `#171716`, the desktop ground averages around `#b9b9b4`, and muted inactive text is `#50504c`. Paper-on-carbon ownership rails exceed 16:1 contrast; carbon against the desktop ground exceeds 9:1.

The shell uses Omarchy's existing legible type system. Weight, title case, grouping, and inversion create hierarchy. Paper Jam does not imitate Chicago, Geneva, or other proprietary period typography.

## Wallpaper law

Bitmap Workbench 01 is a 3840x2160 two-color raster reduction of a preserved ImageGen master. It uses carbon and warm paper only; ordered marks and hard nearest-neighbor enlargement keep the illustrated pixel construction visible at desktop scale. Large forms live primarily in the upper-right, lower-right, and lower-left perimeter while the central 50% remains a low-noise application field.

The artwork contains no Apple marks, copied desktop tiles, historical devices, text, logos, fake UI, gradients, or smooth gray effects. The untouched generation master and prompt are retained under `artwork/imagegen/`; the theme picker preview is wallpaper-only and is never described as runtime evidence.

## Motion laws

- Selection, hover, and focus feedback is immediate or near-immediate.
- Dock reveal may translate vertically once; it does not magnify, bounce, or spring.
- Overview entry uses a short linear opacity or position change without blur or overshoot.
- Active-application rail changes use a short linear width transition.
- Paper Jam keeps motion brief and linear. Omarchy does not currently expose a host-level reduced-motion signal to plugins, so honoring one remains an explicit integration follow-up rather than a claimed feature.

## Provenance guardrails

- No Apple, Finder, Happy Mac, Command-key, or copied Susan Kare artwork or product naming.
- No original desktop tiles, exact striped title rhythm, system sounds, logos, device silhouettes, or proprietary typefaces.
- No beige-monitor costume, CRT curvature, scanlines, phosphor glow, sepia, or synthwave gradients.
- Original object illustrations use a shared bitmap scale and dither system but do not recreate Apple silhouettes, proportions, badges, faces, or pixel decisions.
- Modern application content and meaningful icons are not forced into historical monochrome.

## Success checks

- Single click never opens a desktop object; double-click and Return do.
- A selected generic object changes both its glyph state and its name rail.
- A selected picture file reverses the dedicated bitmap picture icon and its name rail.
- Overview selection never changes the preview body's value.
- The active overview window is distinguishable from the keyboard-selected window when they differ.
- The top rail's primary identity is the application, not only the document title.
- Enter and Escape in the trust dialog always cancel.
- Unavailable plugin-menu actions remain visible and dimmed in stable positions.
- Desktop labels remain legible over every supported wallpaper crop.
- The wallpaper's icon lane, central field, and dock zone remain usable under 16:9, 16:10, 21:9, and 4:3 cover crops, with no moire or edge shimmer at 100%, 125%, or 200% scaling.
- Disabling the plugin restores the stock shell without deleting desktop files or compatibility state.

## Non-goals

- Pixel-perfect reproduction of System 1, Finder, or any Apple operating system.
- Universal client title-bar styling or a global application menu.
- Replacing Omarchy's tiling model, launcher, Quick Look, controls, or update path.
- A font package, sound set, replacement shell root, or parallel configuration system.
