# Pocket book identity

The app icon is an original smiling open book tucked into a pocket: a small, friendly study companion. It uses the app's cyan palette and contains no letters or SF Symbols. The broad silhouette and simple face remain recognizable at home-screen sizes.

- `AppIcon-Light.svg`, `AppIcon-Dark.svg`, `AppIcon-Tinted.svg` are editable vector sources.
- The corresponding opaque 1024 × 1024 PNGs live in `Resources/Assets.xcassets/AppIcon.appiconset`.
- iOS supplies the corner mask. The exported artwork keeps its full square background.
- Light, dark and tinted appearances share identical geometry.

Regenerate both SVG and PNG from the same original Core Graphics paths on macOS:

```sh
swift Scripts/generate-app-icon.swift
```

The Figma component set is [Brand / Pocket book app icon](https://www.figma.com/design/bYd2T51eVSh9tDzzehJtMa/IETLS_Study?node-id=122-2766).

## Loading motion

`LoadingBookMascot` uses a display-driven `TimelineView.animation` with a 1/60-second minimum interval. Its sine-wave motion remains continuous across generated sections: ±7 pt vertically and ±5° of rotation, with a period of about 3.49 seconds. Actual frame rate depends on the device and system scheduling.

Only the small illustration redraws at animation cadence. Progress text updates once per second. Reduce Motion and inactive scenes pause the animation schedule. No shader, video decoder or additional runtime dependency is required.
