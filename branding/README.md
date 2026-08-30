# One-Bit Bureau branding

`one-bit-bureau-mark.png` is the deterministic 512×512 reduction of the original ImageGen master at `artwork/imagegen/one-bit-bureau-brand-source.png`. It depicts a tiny mechanical office bureau filing one oversized square data bit, rendered in the same warm-paper and carbon language as the app icon pack. It contains no Apple logo, letterform, or copied historical system artwork.

`about.txt` and `screensaver.txt` are generated from the separate ImageGen micro-mark at `artwork/imagegen/one-bit-bureau-brand-text-source.png` with Omarchy’s `omarchy-transcode-ascii` implementation in block mode. That deliberately simplified one-bit master preserves the same recognizable mechanical silhouette at terminal resolution. Setup backs up and applies the results to Omarchy’s documented branding paths. `themes/one-bit-bureau/unlock.png` and `preview-unlock.png` are the matching transparent unlock mark and 1920×1080 native Plymouth preview.

Run `python3 artwork/render-branding.py` with `OMARCHY_PATH` pointing to an Omarchy checkout to reproduce every branded derivative. The full mark remains the creative master for raster surfaces; the micro-mark is used only where terminal-scale legibility requires a simpler source.

The full-mark generation prompt specified an original centered 1984-era office bureau/filing-cabinet machine filing exactly one oversized black square token, with hard one-bit pixels, sparse checkerboard dithering, transparent padding, and no text, Apple marks, monitor, floppy disk, printer, rollers, gradients, antialiasing, shadows, frame, or watermark. The micro-mark prompt reduced that concept to a two-drawer bureau with one open drawer and one prominent square bit so the silhouette remains legible after ASCII transcoding.
