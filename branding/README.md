# Paper Jam branding

`paper-jam-mark.png` is the deterministic 512×512 reduction of the original ImageGen master at `artwork/imagegen/paper-jam-brand-source.png`. It depicts accordion-folded paper jammed between four mechanical rollers, rendered in the same warm-paper and carbon one-bit language as the app icon pack. It contains no Apple logo, letterform, or copied historical system artwork.

`about.txt` and `screensaver.txt` are generated from the separate ImageGen micro-mark at `artwork/imagegen/paper-jam-brand-text-source.png` with Omarchy’s `omarchy-transcode-ascii` implementation in block mode. That deliberately simplified one-bit master preserves four separated rollers and one uninterrupted zigzag paper path at terminal resolution. Setup backs up and applies the results to Omarchy’s documented branding paths. `themes/paper-jam-84/unlock.png` and `preview-unlock.png` are the matching transparent unlock mark and 1920×1080 native Plymouth preview.

Run `python3 artwork/render-branding.py` with `OMARCHY_PATH` pointing to an Omarchy checkout to reproduce every branded derivative. The full mark remains the creative master for raster surfaces; the micro-mark is used only where terminal-scale legibility requires a simpler source.
