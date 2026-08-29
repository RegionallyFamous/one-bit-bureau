# Paper Jam ’84 artwork

The Bitmap Workbench wallpaper and desktop-object family are ImageGen-authored raster artwork. The untouched generated masters are retained under `artwork/imagegen/`; [BITMAP-WORKBENCH.md](BITMAP-WORKBENCH.md) records their prompts, selection decisions, and deterministic reduction recipe.

Regenerate the shipped 4K wallpaper, picker preview, desktop-object PNGs, selected-state PNGs, and labeled crop proof from the preserved sources with:

```bash
python3 artwork/render-bitmap-workbench.py
```

The preserved modern edition and its source artwork remain available at the `alumina-modern-v1` Git tag. They are intentionally absent from the Paper Jam branch and are never installed by `setup`.
