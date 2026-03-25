import CoreGraphics
import CoreImage
import Foundation
import Metal
import Dispatch

/// Metal atlas consumer that blends temporal samples with a repeating hue palette.
public final class TemporalColorSplitAtlasConsumer {
    public var frameCount: Int
    public var frameSpacing: Int
    public var componentCount: Int

    private struct TemporalColorSplitAtlasUniforms {
        var outputWidth: UInt32
        var outputHeight: UInt32
        var cellWidth: UInt32
        var cellHeight: UInt32
        var columns: UInt32
        var rows: UInt32
        var capacity: UInt32
        var frameCountInAtlas: UInt32
        var frameZeroIndex: UInt32
        var blendFrameCount: UInt32
        var frameSpacing: UInt32
        var componentCount: UInt32
        var padding0: UInt32
    }

    private enum PipelineCache {
        static let lock = NSLock()
        static var pipelines: [ObjectIdentifier: MTLComputePipelineState] = [:]
    }

    private let lock = NSLock()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?

    private var pipeline: MTLComputePipelineState?
    private var outputTexture: MTLTexture?
    private var outputImage: CIImage?

    public init(
        frameCount: Int = 5,
        frameSpacing: Int = 1,
        componentCount: Int = 3,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) {
        self.frameCount = max(1, frameCount)
        self.frameSpacing = max(1, frameSpacing)
        self.componentCount = max(1, componentCount)
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
    }

    public func render(
        snapshot: TemporalTextureAtlasSnapshot,
        outputSize: CGSize
    ) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        guard
            ensurePipeline(),
            ensureOutputTexture(width: width, height: height),
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let pipeline,
            let outputTexture
        else {
            return nil
        }

        var uniforms = TemporalColorSplitAtlasUniforms(
            outputWidth: UInt32(width),
            outputHeight: UInt32(height),
            cellWidth: UInt32(max(1, Int(snapshot.cellSize.width.rounded()))),
            cellHeight: UInt32(max(1, Int(snapshot.cellSize.height.rounded()))),
            columns: UInt32(max(1, snapshot.columns)),
            rows: UInt32(max(1, snapshot.rows)),
            capacity: UInt32(max(1, snapshot.capacity)),
            frameCountInAtlas: UInt32(max(0, snapshot.frameCount)),
            frameZeroIndex: UInt32(max(0, snapshot.frameZeroIndex)),
            blendFrameCount: UInt32(max(1, frameCount)),
            frameSpacing: UInt32(max(1, frameSpacing)),
            componentCount: UInt32(max(1, componentCount)),
            padding0: 0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(snapshot.texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<TemporalColorSplitAtlasUniforms>.stride, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status != .completed {
            let message = commandBuffer.error?.localizedDescription ?? "unknown command buffer failure"
            return nil
        }

        guard let outputImage else { return nil }
        return outputImage.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func ensureOutputTexture(width: Int, height: Int) -> Bool {
        if
            let outputTexture,
            outputTexture.width == width,
            outputTexture.height == height,
            outputImage != nil
        {
            return true
        }

        guard let device else { return false }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage.shaderRead
            .union(.shaderWrite)
            .union(.renderTarget)
        descriptor.storageMode = MTLStorageMode.private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return false
        }

        outputTexture = texture
        outputImage = CIImage(
            mtlTexture: texture,
            options: [CIImageOption.colorSpace: colorSpace]
        )
        return outputImage != nil
    }

    private func ensurePipeline() -> Bool {
        if pipeline != nil {
            return true
        }
        guard let device else { return false }
        pipeline = Self.makePipeline(device: device)
        if pipeline == nil {
        }
        return pipeline != nil
    }

    private static func makePipeline(device: MTLDevice) -> MTLComputePipelineState? {
        let key = ObjectIdentifier(device)

        PipelineCache.lock.lock()
        if let cached = PipelineCache.pipelines[key] {
            PipelineCache.lock.unlock()
            return cached
        }
        PipelineCache.lock.unlock()

        let pipeline: MTLComputePipelineState?
        if
            let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
            let data = try? Data(contentsOf: url),
            let library = try? device.makeLibrary(data: dispatchData(from: data)),
            let function = library.makeFunction(name: "temporalColorSplitAtlasKernel"),
            let compiled = try? device.makeComputePipelineState(function: function)
        {
            pipeline = compiled
        } else {
            pipeline = makePipelineFromSource(device: device)
        }

        guard let pipeline else { return nil }

        PipelineCache.lock.lock()
        PipelineCache.pipelines[key] = pipeline
        PipelineCache.lock.unlock()
        return pipeline
    }

    private static func dispatchData(from data: Data) -> DispatchData {
        var result = DispatchData.empty
        data.withUnsafeBytes { rawBuffer in
            let typed = rawBuffer.bindMemory(to: UInt8.self)
            guard let base = typed.baseAddress else { return }
            result = DispatchData(bytes: UnsafeBufferPointer(start: base, count: typed.count))
        }
        return result
    }

    private static func makePipelineFromSource(device: MTLDevice) -> MTLComputePipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct TemporalColorSplitAtlasUniforms {
            uint outputWidth;
            uint outputHeight;
            uint cellWidth;
            uint cellHeight;
            uint columns;
            uint rows;
            uint capacity;
            uint frameCountInAtlas;
            uint frameZeroIndex;
            uint blendFrameCount;
            uint frameSpacing;
            uint componentCount;
            uint padding0;
        };

        inline float3 hsvToRgb(float3 hsv) {
            float3 rgb = clamp(abs(fmod(hsv.x * 6.0f + float3(0.0f, 4.0f, 2.0f), 6.0f) - 3.0f) - 1.0f, 0.0f, 1.0f);
            rgb = rgb * rgb * (3.0f - 2.0f * rgb);
            return hsv.z * mix(float3(1.0f), rgb, hsv.y);
        }

        kernel void temporalColorSplitAtlasKernel(
            texture2d<float, access::read> atlasTexture [[texture(0)]],
            texture2d<float, access::write> outputTexture [[texture(1)]],
            constant TemporalColorSplitAtlasUniforms& uniforms [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
                return;
            }

            if (uniforms.frameCountInAtlas == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
                outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
                return;
            }

            uint safeSpacing = max(uniforms.frameSpacing, 1u);
            uint safeComponents = max(uniforms.componentCount, 1u);
            uint availableMax = uniforms.frameCountInAtlas > 0 ? uniforms.frameCountInAtlas - 1 : 0;
            uint availableSamples = availableMax / safeSpacing + 1;
            uint sampleCount = min(max(uniforms.blendFrameCount, 1u), max(availableSamples, 1u));

            float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
            float2 uv = (float2(gid) + 0.5f) / outSize;
            uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
            uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

            float3 sumRGB = float3(0.0f);
            float sumAlpha = 0.0f;
            for (uint sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
                uint offset = min(sampleIndex * safeSpacing, availableMax);
                uint wrappedOffset = uniforms.capacity > 0 ? (offset % uniforms.capacity) : 0;
                uint absoluteIndex = (uniforms.frameZeroIndex + uniforms.capacity - wrappedOffset) % uniforms.capacity;
                uint col = absoluteIndex % uniforms.columns;
                uint row = absoluteIndex / uniforms.columns;
                uint atlasX = col * uniforms.cellWidth + cellX;
                uint atlasY = row * uniforms.cellHeight + cellY;
                float4 sampleColor = atlasTexture.read(uint2(atlasX, atlasY));

                uint paletteIndex = sampleIndex % safeComponents;
                float hue = float(paletteIndex) / float(safeComponents);
                float3 tint = hsvToRgb(float3(hue, 1.0f, 1.0f));

                sumRGB += sampleColor.rgb * tint;
                sumAlpha += sampleColor.a;
            }

            float normalization = 1.0f / float(sampleCount);
            outputTexture.write(float4(sumRGB * normalization, sumAlpha * normalization), gid);
        }
        """

        guard
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "temporalColorSplitAtlasKernel")
        else {
            return nil
        }

        return try? device.makeComputePipelineState(function: function)
    }
}
