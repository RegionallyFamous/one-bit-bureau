# One-Bit Bureau artwork

The Bitmap Workbench wallpaper family and desktop-object family are ImageGen-authored raster artwork. The untouched generated masters are retained under `artwork/imagegen/`; [BITMAP-WORKBENCH.md](BITMAP-WORKBENCH.md) records their prompts, selection decisions, and deterministic reduction recipe.

Regenerate both shipped 4K wallpapers, the picker preview, desktop-object PNGs, selected-state PNGs, and labeled crop proofs from the preserved sources with:

```bash
python3 artwork/render-bitmap-workbench.py
```
