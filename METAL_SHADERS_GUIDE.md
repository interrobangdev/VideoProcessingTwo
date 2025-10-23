# Metal Shaders in Swift Packages - Implementation Guide

This document explains how to use CoreImage Metal filters in a Swift Package, which was implemented for the VideoProcessingTwo framework.

## The Challenge

Using Metal shaders with CoreImage in Swift Packages requires special handling because:
1. `Bundle.module` doesn't automatically compile `.metal` files
2. CIKernel requires pre-compiled `.metallib` binary data
3. Swift Package Manager doesn't have built-in Metal compilation

## Our Solution: Pre-Compiled Metal Libraries

We use a hybrid approach that pre-compiles Metal shaders to `.metallib` format and bundles them as package resources.

### Implementation Steps

#### 1. Package.swift Configuration

Add both the source `.metal` file and compiled `.metallib` as resources:

```swift
.target(
    name: "VideoProcessingTwo",
    resources: [
        .process("Filters/Shaders.metal"),      // Source (for reference)
        .process("Filters/Shaders.metallib")     // Compiled binary
    ]
)
```

#### 2. Compilation Script

We created `compile_shaders.sh` to compile Metal shaders:

```bash
#!/bin/bash
set -e

METAL_SOURCE="$SCRIPT_DIR/Sources/Filters/Shaders.metal"
OUTPUT_FILE="$OUTPUT_DIR/Shaders.metallib"

# Compile to AIR (Apple Intermediate Representation)
xcrun -sdk macosx metal -c "$METAL_SOURCE" -o "$OUTPUT_DIR/Shaders.air"

# Link to metallib
xcrun -sdk macosx metallib "$OUTPUT_DIR/Shaders.air" -o "$OUTPUT_FILE"
```

**Usage:**
```bash
chmod +x compile_shaders.sh
./compile_shaders.sh
```

#### 3. Loading in Swift

The GlitchFilter loads the pre-compiled `.metallib`:

```swift
class GlitchFilter: CIFilter {
    private static var cachedKernel: CIKernel?

    private static func createKernel() -> CIKernel? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        do {
            // Load pre-compiled .metallib from bundle
            if let url = Bundle.module.url(forResource: "Shaders",
                                          withExtension: "metallib",
                                          subdirectory: "Filters"),
               let data = try? Data(contentsOf: url) {
                return try CIKernel(functionName: "glitchEffect",
                                  fromMetalLibraryData: data)
            }

            print("Pre-compiled .metallib not found. Run ./compile_shaders.sh")
            return nil
        } catch {
            print("Failed to create Metal kernel: \(error)")
            return nil
        }
    }

    override var outputImage: CIImage? {
        guard let inputImage = inputImage, let kernel = kernel else { return nil }
        return kernel.apply(extent: inputImage.extent,
                          roiCallback: { _, rect in return rect },
                          arguments: [inputImage, intensity])
    }
}
```

#### 4. Metal Shader Format

CoreImage Metal shaders must follow this format:

```metal
#include <metal_stdlib>
using namespace metal;

extern "C" {
    namespace coreimage {
        float4 glitchEffect(sampler src, float intensity) {
            float2 coord = destCoord();
            // Your shader logic here
            return color;
        }
    }
}
```

**Key points:**
- Use `extern "C"` and `namespace coreimage`
- Use `sampler` type for image inputs
- Use `destCoord()` to get current pixel coordinates
- Return `float4` for RGBA output

## Development Workflow

### First Time Setup
1. Write your Metal shader in `Sources/Filters/Shaders.metal`
2. Run `./compile_shaders.sh` to generate `.metallib`
3. Commit both `.metal` and `.metallib` to version control

### After Shader Changes
1. Edit `Sources/Filters/Shaders.metal`
2. Run `./compile_shaders.sh` to recompile
3. Rebuild the Swift package: `swift build`

### Adding New Shaders
1. Add function to `Shaders.metal`
2. Recompile with `./compile_shaders.sh`
3. Create a new CIFilter subclass that loads it:
```swift
return try CIKernel(functionName: "yourNewShader",
                  fromMetalLibraryData: data)
```

## Alternative Approaches (Not Used)

### Option A: Runtime Compilation
Compile Metal source at runtime using `MTLDevice.makeLibrary(source:)`.
- **Pros:** No pre-compilation needed
- **Cons:** Can't easily get binary data for CIKernel

### Option B: Embedded String Constants
Store Metal code as Swift string constants.
- **Pros:** Simple, no external files
- **Cons:** Loses syntax highlighting, harder to maintain

### Option C: Build Phase Scripts
Use SPM plugins to compile during build.
- **Pros:** Automatic compilation
- **Cons:** Complex setup, requires Swift 5.6+

## Troubleshooting

### "Bundle.module not found"
- Make sure Package.swift includes resources
- Clean build folder: `swift package clean`

### "Function not found in library"
- Check function name matches exactly
- Verify `.metallib` is up to date: `./compile_shaders.sh`

### "Metal not supported"
- Ensure running on Mac OS 10.11+ or iOS 9+
- Check `MTLCreateSystemDefaultDevice()` returns non-nil

## Performance Notes

- **Kernel caching:** We cache the compiled kernel in a static variable to avoid recompilation
- **Bundle resources:** `.metallib` files are copied to bundle only once during build
- **First use:** Slight delay when creating kernel, then cached for subsequent uses

## References

- [Apple Metal Documentation](https://developer.apple.com/metal/)
- [CoreImage Kernel Programming Guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageKernelLanguageReference/)
- [Swift Package Manager Resources](https://github.com/apple/swift-evolution/blob/main/proposals/0271-package-manager-resources.md)
