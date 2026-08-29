# Bitmap Workbench raster sources

Bitmap Workbench 01 and the desktop-object family were generated with the built-in OpenAI ImageGen tool, then selected and reduced locally into exact runtime assets. The untouched selected generations live under `artwork/imagegen/`.

## Wallpaper prompt

The selected wallpaper prompt requested an original orthographic one-bit machine-garden worktable with overlapping paper sheets, cables, trays, mechanical leaves, and abstract mechanisms around a calm central field. It required a quiet left icon lane and bottom-center shelf zone, hard aliased bitmap construction, ordered black-and-white dithering, and no UI, text, logos, faces, computers, historical hardware, Apple imagery, Susan Kare imagery, gradients, smooth gray, haze, or watermark.

The first generation was rejected because its left icon lane was too busy and two mechanical details read as faces. The selected third pass removed those forms, protected the leftmost 16%, preserved the center, and added one compact lower-left organizer outside the icon lane so the composition remains visible behind ordinary windows.

## Desktop-object atlas prompt

The atlas prompt requested seven original transparent one-bit mini-illustrations in a four-column by two-row grid: side-tab folder, folded-corner document, linked rectangular loops, launcher aperture and arrow, removable volume, archive box, and open slatted wastebasket. It required distinct silhouettes, consistent optical weight, hard aliased edges, ordered dither, generous alpha padding, and no labels, faces, logos, historical Apple or Susan Kare shapes, gradients, blur, or fake UI.

## Image fallback prompt

The separate fallback prompt requested one original square picture-frame object with a mountain-and-sun aperture, using the same chunky one-bit edge scale, dither density, optical weight, and transparent padding as the atlas. It explicitly prohibited text, logos, faces, Apple marks, historical icon copies, gradients, smooth vector lines, shadows, and extra objects. `bitmap-image-fallback-source.png` is the untouched selected transparent generation; the runtime renderer derives both normal and selected 64px states from it.

## Runtime reduction

- Wallpaper: threshold the selected source at 60% luminance, map dark pixels to `#171716` and light pixels to `#f4f4f0`, then enlarge to 3840x2160 with nearest-neighbor sampling.
- Preview: resize the reduced 4K wallpaper to 1600x900 with Lanczos sampling; this is an honest wallpaper-only picker preview, not runtime evidence.
- Objects: split the transparent atlas into its four-by-two cells, then reduce the seven occupied cells plus the separate image-fallback source. Hard-threshold alpha and luminance, map to carbon/paper, trim, reduce each illustration into a 56x56 content box with nearest-neighbor sampling, and center it on a transparent 64x64 canvas.
- Selected objects: use the same thresholded silhouettes with carbon and paper exchanged. The QML selection plate supplies the surrounding carbon field.

No vectorization or manual tracing was used in this revision. The generated sources remain available for a later authored vector or hand-pixel cleanup pass.

Run `python3 artwork/render-bitmap-workbench.py` from the repository root to reproduce every shipped derivative from the preserved sources.
