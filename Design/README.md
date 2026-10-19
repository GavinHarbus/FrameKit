# FrameKit artwork

- `FrameKit-AppIcon.png`: prepared 1024 × 1024 app icon with transparent outer padding.

The public master preserves the blue tile and white artwork, centered for Dock and Finder use. The original presentation file is kept outside the public repository.

The macOS AppIcon catalog contains all ten 1×/2× slots from 16pt to 512pt. Regenerate from the repository root with:

```bash
swift Tools/GenerateAppIcon.swift
```

The generation tool reads the prepared master and resizes it for the asset catalog. It does not need the original presentation file or its embedded provenance metadata.

## Artwork license

Copyright (c) 2026 Gavin Schnee Studio. All rights reserved.

The FrameKit logo and app icon images in this directory and in
`Resources/Assets.xcassets/AppIcon.appiconset/` are excluded from the repository's
MIT license. They may be used when building an unmodified copy of FrameKit for
personal use, or to identify FrameKit accurately in a review, tutorial, or link
to the official product. Other reuse or redistribution of this artwork requires
permission. Use your own artwork for redistributed forks.

Source code, icon-generation tools, and documentation remain under the
[MIT License](../LICENSE). This notice does not grant rights to imply that a
modified or redistributed app is an official or endorsed FrameKit release.
