# VideoProcessingTwo

A powerful, production-ready Swift video composition and effects library for iOS (15+) and macOS (11+). Built on a decade of experience crafting professional video pipelines, VideoProcessingTwo combines the flexibility of Core Image with the performance of Metal shaders, all wrapped in an intuitive hierarchical composition API.

## Features

### Hierarchical Composition Architecture
Organize complex video projects with unlimited nesting depth:
- **Composition** → **VideoScene** → **LayerGroup** (recursive) → **Layer** → **Surface** → **Source**
- Apply filters at any level in the hierarchy with proper inheritance
- Supports layer masking for advanced compositing

### Rich Media Sources
Mix multiple input types seamlessly in a single composition:
- **Images** - Static images with configurable duration
- **Videos** - Full video playback with looping, frame-accurate seeking, and AVVideoComposition integration
- **Animated GIFs** - With intelligent frame caching and proper timing
- **Text** - Rich text rendering with 8 animation types (fade, slide, rotate, scale, swap), custom fonts, colors, backgrounds, and stroke effects
- **Live Camera** - Real-time camera capture with exposure, zoom, torch, and flash controls (iOS)

### Professional Filter System
14+ built-in filters with real-time parameter animation:
- **Core Image Filters**: Gaussian Blur, Color Adjustment (brightness/contrast/saturation), Crystallize effect, Voronoi stylize
- **Custom Metal Shaders**: Glitch effects with intensity control and pixelation
- **Geometric**: Rotate, Scale, Translate with center-point control
- **Visual Effects**: Fade, Glitch with color shifts

### Advanced Animation System
Drive filter parameters with precision control:

**Bezier Path-Based Easing**
- Define complex animation curves with multiple control points and handles
- Create professional ease-in, ease-out, custom bounce, and other timing curves
- Per-frame evaluation for smooth interpolation

**Arbitrary Input Drivers** *(Extensible Framework)*
- Vision Framework integration: Animate based on detected poses, hands, faces, objects
- Audio data driver: Synchronize effects to music or sound
- Custom drivers: Build your own parameter animation sources
- Keyframe system with start/end times and tween function support

### Export Capabilities
- **Video Export** - H.264/MP4 with configurable bitrate and automatic size optimization
- **GIF Export** - Animated GIFs with frame timing preservation
- Real-time frame callbacks for progress monitoring and advanced workflows
- Scene composition with temporal offsetting for multi-segment videos

### Cross-Platform & Modern Architecture
- Unified API for iOS and macOS
- Metal/CoreImage rendering with GPU acceleration
- Custom pixel buffer management and thread-safe export pipelines
- Rich geometry extensions for intuitive transforms and positioning
- Frame abstraction supporting multiple representations (UIImage, CVPixelBuffer, CGImage)

### Live Rendering
- SwiftUI Metal view support for real-time preview
- Full camera pipeline integration
- Frame-accurate playback with filter preview

## Architecture

The library uses a sophisticated rendering pipeline:

1. **Composition Graph** - Hierarchical structure of groups, layers, and effects
2. **Metal Environment** - Singleton GPU context managing rendering resources
3. **Frame Compositor** - Orchestrates per-frame rendering with timing precision
4. **Layer Rendering** - Recursive group rendering with filter application and blending
5. **Export Pipeline** - Converts frames to video or GIF with proper encoding

## Quick Start

```swift
// Create a composition
let composition = Composition()
let scene = VideoScene(duration: 10, frameRate: 30, outputSize: CGSize(width: 1080, height: 1920))

// Build a composition with multiple sources
let videoLayer = Layer()
videoLayer.addSurface(Surface(source: VideoSource(url: videoURL)))

let textLayer = Layer()
textLayer.addSurface(Surface(source: TextSource(text: "Hello Video")))

let group = LayerGroup()
group.addLayer(videoLayer)
group.addLayer(textLayer)

scene.group = group

// Add animated effects
let blur = GaussianBlur(radius: 10)
let animator = FilterAnimator(startTime: 0, endTime: 5, value: .singleValue(0))
blur.filterAnimators = [animator]
group.filters.append(blur)

// Export to video
let exporter = ExportManager()
exporter.exportComposition(composition, scenes: [scene], outputURL: outputURL) { progress in
    print("Export progress: \(progress)")
}
```

## Installation

Add VideoProcessingTwo to your `Package.swift`:

```swift
.package(url: "https://github.com/yourusername/VideoProcessingTwo.git", from: "1.0.0")
```

Or in Xcode, use File → Add Packages and enter the repository URL.

## Requirements

- iOS 15.0+ or macOS 11.0+
- Swift 5.5+
- Xcode 13.0+

## Use Cases

- Video editing applications
- Social media content creation tools
- Real-time video effects processing
- Educational video generation
- Professional video composition workflows
- Live streaming applications with effects

## Design Philosophy

Built on lessons learned from a decade of video pipeline development, VideoProcessingTwo prioritizes:
- **Simplicity** - Intuitive APIs that hide complexity
- **Performance** - GPU-accelerated rendering with efficient memory management
- **Flexibility** - Extensible filter system and arbitrary animation drivers
- **Quality** - Production-ready export with professional codec support
- **Cross-Platform** - Write once, deploy to iOS and macOS

## License

VideoProcessingTwo is released under the BSD-3-Clause License. See the LICENSE file for details.
