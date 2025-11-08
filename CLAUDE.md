# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

VideoProcessingTwo is a Swift package for video composition, filtering, and export. It supports cross-platform development for iOS (15+) and macOS (11+). The library provides a hierarchical scene-based architecture for creating complex video compositions with layers, groups, filters, and various media sources.

## Build and Development Commands

This is a Swift Package Manager (SPM) project. Common commands include:

```bash
# Build the package
swift build

# Run tests
swift test

# Run specific test
swift test --filter VideoProcessingTwoTests.testName

# Build for release
swift build -c release

# Clean build artifacts
swift package clean

# Generate Xcode project (if needed)
swift package generate-xcodeproj
```

## Architecture Overview

### Core Hierarchy
The composition system follows a hierarchical structure:
- **Composition**: Top-level container with scenes and output configuration
- **VideoScene**: Time-based container with duration, frame rate, and a root group
- **Group**: Container for layers and nested groups, supports filters and masks
- **Layer**: Contains surfaces (media elements) that are composited together
- **Surface**: Wraps a Source with positioning (frame, rotation)
- **Source**: Protocol for media providers (Image, Video, GIF, Text)

### Key Components

#### Media Sources (`Sources/`)
- `ImageSource.swift`: Static image rendering
- `VideoSource.swift`: Video file playback
- `GIFImageSource.swift`: Animated GIF support
- `TextSource.swift`: Text rendering with customization
- `Frame.swift`: Platform-agnostic image wrapper with `ciImageRepresentation()`

#### Rendering Pipeline (`Sources/`)
- `FrameCompositor.swift`: Main export engine for video/GIF generation
- `MetalEnvironment.swift`: Metal/CoreImage rendering context (singleton pattern)
- `MovieWriter.swift`: H.264 video encoding with pixel buffer management
- `GIFWriter.swift`: Animated GIF creation and export
- `Group.swift`: Hierarchical composition with filter application
- `Layer.swift`: Surface composition within layers

#### Utilities (`Sources/`)
- `CompositionHelper.swift`: Helper functions for composition setup
- `ExportManager.swift`: High-level export coordination
- `CameraManager.swift`: Camera integration for real-time capture

#### Filters (`Sources/Filters/`)
- `Filter.swift`: Protocol defining filter interface with `filterContent()` method
- `FilterAnimator.swift`: Keyframe animation system with tween functions
  - Supports three animation types: `SingleValue`, `Point`, `Rect`
  - Uses `TweenFunctionProvider` for interpolation (e.g., `LinearFunction`)
  - Animations are evaluated per-frame in `Group.renderGroup()`
- Individual filters: `GaussianBlur.swift`, `ColorAdjustment.swift`, `GlitchEffect.swift`, `Fade.swift`, `Scale.swift`, `Rotate.swift`, `Translate.swift`, etc.
- `Shaders.metal`: Custom Metal shaders for advanced effects

#### Platform Abstraction (`Sources/`)
- `PlatformTypes.swift`: Cross-platform type definitions (`PlatformImage`, `PlatformFont`, `PlatformColor`)
- `Sources/Extensions/`: Cross-platform extensions
  - `CGExtensions.swift`: CoreGraphics utilities for geometry operations
  - `CIImage+Extensions.swift`: CoreImage helpers for image manipulation
  - `CVPixelBuffer+Extensions.swift`: Pixel buffer utilities
  - `CGImage+Extensions.swift`: CGImage conversion helpers
  - `Double+Extensions.swift`: Time conversion utilities (e.g., `cmTime()`)

### Rendering Flow
1. `FrameCompositor.exportScene()` is called with output type (video or GIF)
2. For video: `MovieWriter` is initialized with H.264 encoding settings
3. For GIF: `GIFWriter` is initialized with frame count
4. `generateFrames()` iterates through each frame at the specified frame rate
5. For each frame time, `VideoScene.group.renderGroup()` is called:
   - Groups recursively render child groups and layers
   - Layers composite their surfaces using CoreImage's `composited(over:)`
   - Source objects provide frames via `getFrameAtTime(cmTime:)`
   - Filters apply effects with animated properties updated via `FilterAnimator.tweenValue()`
6. For video: Frame is rendered to pixel buffer via `MetalEnvironment.shared.context.render()` and appended
7. For GIF: Frame is converted to CGImage and added with delay timing
8. Export completes with `MovieWriter.finishWriting()` or `GIFWriter.finalize()`

### Layer Indexing System
`LayerObjectIndex.swift` provides hierarchical addressing:
- `groupIndices`: Array path to nested groups
- `layerIndex`: Target layer within the group
- Used by `Scene.getGroup()` and `Scene.getGroupLayer()` for navigation

## Development Patterns

### Adding New Media Sources
Implement the `Source` protocol:
```swift
public protocol Source {
    func getFrameAtTime(cmTime: CMTime) -> Frame?
}
```

### Adding New Filters
Implement the `Filter` protocol with animation support:
```swift
public protocol Filter {
    var filterAnimators: [FilterAnimator] { get set }
    func updateFilterValue(filterProperty: FilterProperty, value: Any)
    func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage?
}
```

### Cross-Platform Considerations
- Use `PlatformImage`, `PlatformColor`, and `PlatformFont` from `PlatformTypes.swift`
- Leverage conditional compilation (`#if canImport(UIKit)` vs `#elseif canImport(AppKit)`)
- Extensions in `Sources/Extensions/` provide unified APIs across platforms
- `PlatformGraphics` provides cross-platform context creation utilities

### Animation System
- `FilterAnimator` handles property interpolation between keyframes:
  - `startTime` and `endTime` define the animation duration
  - `tweenFunctionProvider` controls easing (default: `LinearFunction`)
  - Three value types: `SingleValue` (Double), `Point` (CGPoint), `Rect` (CGRect)
- Filters check `filterAnimators` array during `Group.renderGroup()` and update values via `updateFilterValue()`
- Custom tween functions can be created by implementing `TweenFunctionProvider` protocol

### Video Export Details
- `MovieWriter` uses AVAssetWriter with H.264 codec
- Video dimensions are automatically adjusted to even numbers (H.264 requirement)
- Pixel buffers are created from `AVAssetWriterInputPixelBufferAdaptor` pool
- All writing happens on a dedicated serial queue (`writerQueue`) for thread safety
- Export supports frame callbacks for progress monitoring

## Testing

Tests are located in `Tests/VideoProcessingTwoTests/`. The project uses XCTest framework. Run tests with `swift test` or through Xcode.