.pragma library

// Reuse the battle-tested dock model and only tune the geometry used by the
// visual refinement branch. Keeping the original implementation in
// DockModelBase.js avoids duplicating ordering, drag and persistence logic.
Qt.include("DockModelBase.js")

LAYOUT_OPTS.slotWidth = 52
LAYOUT_OPTS.spacing = 0
LAYOUT_OPTS.iconSize = 44
LAYOUT_OPTS.hoverScale = 1
LAYOUT_OPTS.radius = 1
LAYOUT_OPTS.sidePadding = 8
LAYOUT_OPTS.separatorWidth = 8
