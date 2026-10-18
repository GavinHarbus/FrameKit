# FrameKit artwork

- `FrameKit-logo-original.png`: supplied original, preserved without modification (1254 × 1254).
- `FrameKit-AppIcon.png`: prepared 1024 × 1024 app icon with transparent outer padding.

The application icon preserves the supplied blue tile and white artwork. The white presentation background and its baked-in outer shadow are removed, and the tile is centered for Dock/Finder use. This is a raster icon, not a layered Icon Composer asset.

The macOS AppIcon catalog contains all ten 1×/2× slots from 16pt to 512pt. Regenerate from the repository root with:

```sh
swift Tools/GenerateAppIcon.swift
```

The preparation script is specific to this artwork. A transparent or layered original should replace this extraction if one becomes available.
