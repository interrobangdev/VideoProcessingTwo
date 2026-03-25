# VideoProcessingTwo

`VideoProcessingTwo` is a Swift package for building layered video scenes on iOS and macOS with Core Image, Metal, and AVFoundation. It gives you a small composition model for arranging sources, applying filters, previewing frames, and exporting finished output as video or GIF.

## What It Supports

- Hierarchical scene composition with `VideoScene`, `LayerGroup`, `Layer`, and `Surface`
- Multiple source types in the same scene:
  - `VideoSource`
  - `ImageSource`
  - `GIFImageSource`
  - `TextSource`
  - `CameraSource` on iOS
- Built-in filters for blur, color adjustment, transforms, fades, crystallize, and glitch-style effects
- Animated filter values with `FilterAnimator`, `LinearFunction`, and Bezier tween helpers
- Export to `.mp4` video or animated GIF
- Metal-backed rendering utilities, including a SwiftUI `MetalView` for live preview on iOS
- AVFoundation composition helpers for integrating with `AVVideoComposition`

## Architecture

The package is centered around a scene graph:

`VideoScene -> LayerGroup -> Layer -> Surface -> Source`

- A `VideoScene` defines duration, frame rate, and render size.
- A `LayerGroup` can contain nested groups, layers, filters, and an optional mask.
- A `Layer` composites one or more `Surface` values.
- A `Surface` places a `Source` into a rectangle with rotation.
- A `Source` provides frames over time.

This keeps the rendering model simple while still supporting nested compositions and scene-level effects.

## Quick Start

```swift
import CoreGraphics
import VideoProcessingTwo

let renderSize = CGSize(width: 1080, height: 1920)
let scene = VideoScene(duration: 5, frameRate: 30, size: renderSize)

let videoSource = VideoSource(url: videoURL)
videoSource.compositionStartTime = 0
videoSource.duration = 5

let titleSource = TextSource(
    words: ["Hello", "from", "VideoProcessingTwo"],
    canvasSize: renderSize,
    wordDuration: 0.8,
    animationType: .fadeInOut,
    maxCharacters: 18
)
titleSource.compositionStartTime = 0
titleSource.duration = 5

let videoLayer = Layer(surfaces: [
    Surface(
        source: videoSource,
        frame: CGRect(origin: .zero, size: renderSize),
        rotation: 0
    )
])

let textLayer = Layer(surfaces: [
    Surface(
        source: titleSource,
        frame: CGRect(x: 120, y: 760, width: 840, height: 240),
        rotation: 0
    )
])

let blur = GaussianBlur(radius: 0, filterAnimators: [])

scene.group = LayerGroup(
    groups: [],
    layers: [videoLayer, textLayer],
    filters: [blur],
    mask: nil
)

ExportManager.shared.exportScene(
    scene: scene,
    outpuURL: outputURL,
    progress: { sceneID, progress in
        print("Exporting \\(sceneID): \\(progress)")
    },
    completion: { success in
        print("Finished: \\(success)")
    }
)
```

## Sources

### Video

`VideoSource` supports:

- Time-windowed playback inside a composition
- Source offsets with `sourceStartTime`
- Looping behavior during export
- Track-based integration for `AVVideoComposition` workflows

### Images and GIFs

- `ImageSource` displays a still image for a configurable duration
- `GIFImageSource` plays animated GIFs with timing-aware frame selection and optional looping

### Text

`TextSource` can animate words or short phrases with:

- Swap
- Fade in/out
- Slide left/right/up/down
- Rotate in
- Scale in

It also supports font, color, alignment, optional background color, and stroke styling.

### Camera

`CameraSource` and `CameraManager` provide live camera frames on iOS for preview-driven workflows and real-time composition.

## Filters and Animation

Included filters currently live under `Sources/Filters` and include:

- `GaussianBlur`
- `ColorAdjustment`
- `Crystallize`
- `Rotate`
- `Scale`
- `Translate`
- `Fade`
- `GlitchEffect`

Animated filter values are driven by `FilterAnimator`. The package currently includes:

- Linear interpolation with `LinearFunction`
- Bezier-based tweening with `BezierPathTweenFunction` and `CubicBezierTweenFunction`

## Export

For most usage, `ExportManager` is the main export entry point:

- Queue one or more scene exports
- Receive progress callbacks per scene
- Export rendered output to video

For lower-level control, `FrameCompositor` can export:

- H.264 video
- Animated GIF
- Per-frame callbacks during render

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/interrobangdev/VideoProcessingTwo.git", from: "1.0.0")
```

Or add it in Xcode with **File -> Add Package Dependencies...** and use:

`https://github.com/interrobangdev/VideoProcessingTwo.git`

## Requirements

- iOS 15.0+ or macOS 11.0+
- Swift 5.10+
- Xcode 15+

## Sample Project

If you want to see this package used in a real app, check out the companion sample project:

[VideoProcessingTwoSamples](https://github.com/interrobangdev/VideoProcessingTwoSamples)

## License

VideoProcessingTwo is released under the BSD-3-Clause License. See [LICENSE](LICENSE) for details.
