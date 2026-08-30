# One-Bit Bureau app icon pack

The twelve app-role illustrations are original ImageGen outputs made for One-Bit Bureau on 2026-08-29. Each source was generated separately on a transparent square canvas with no logos, letters, trademarks, platform marks, gradients, drop shadows, or color beyond warm paper and near-black carbon.

The shared prompt contract was: an original late-1984-inspired one-bit bitmap illustration for a generic application role, chunky black pixel contours, sparse ordered dithering, warm off-white paper fill, strict frontal or slight three-quarter silhouette, readable at 48–64 pixels, no imitation of a specific historical system icon. Role-specific objects were then requested for Files, Terminal, Web, Code, Mail, Chat, Music, Video, Calendar, Controls, Games, and Notes.

`render-app-icons.py` trims the transparent ImageGen masters and deterministically produces 256×256 PNGs with consistent optical scale. The installed dock consumes only the rendered files under `components/dock/assets/app-icons/`; the source masters remain in `artwork/imagegen/app-icons/` for later hand-pixeling or vectorization.

`video-rejected-source.png` is intentionally not part of the pack. It was rejected because the projected-light form introduced a hand-like ambiguity and a weaker silhouette than the final reel-and-viewer design.
