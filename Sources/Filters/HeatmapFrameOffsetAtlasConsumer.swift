import CoreGraphics
import CoreImage
import Foundation
import Metal
import Dispatch

/// Metal atlas consumer that uses a heatmap image's red channel to drive the
/// per-pixel frame offset sampled from a temporal atlas.
public final class HeatmapFrameOffsetAtlasConsumer {
    public var maxFrameOffset: Int

    private struct HeatmapFrameOffsetUniforms {
        var outputWidth: UInt32
        var outputHeight: UInt32
        var cellWidth: UInt32
        var cellHeight: UInt32
        var columns: UInt32
        var rows: UInt32
        var capacity: UInt32
        var frameCount: UInt32
        var frameZeroIndex: UInt32
        var maxFrameOffset: UInt32
        var padding0: UInt32
        var padding1: UInt32
        var padding2: UInt32
    }

    private enum PipelineCache {
        static let lock = NSLock()
        static var pipelines: [ObjectIdentifier: MTLComputePipelineState] = [:]
    }

    private let lock = NSLock()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?

    private var pipeline: MTLComputePipelineState?
    private var outputTexture: MTLTexture?
    private var outputImage: CIImage?
    private var heatmapTexture: MTLTexture?

    public init(
        maxFrameOffset: Int = 24,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) {
        self.maxFrameOffset = max(0, maxFrameOffset)
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        if let device {
            self.context = CIContext(
                mtlDevice: device,
                options: [CIContextOption.cacheIntermediates: false]
            )
        } else {
            self.context = CIContext(options: [CIContextOption.cacheIntermediates: false])
        }
    }

    public func render(
        snapshot: TemporalTextureAtlasSnapshot,
        outputSize: CGSize,
        heatmapImage: CIImage
    ) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }

        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))
        guard heatmapImage.extent.width > 0, heatmapImage.extent.height > 0 else {
            return nil
        }

        guard
            ensurePipeline(),
            ensureOutputTexture(width: width, height: height),
            ensureHeatmapTexture(width: width, height: height),
            let context,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let pipeline,
            let outputTexture,
            let heatmapTexture
        else {
            return nil
        }

        let outputRect = CGRect(x: 0, y: 0, width: width, height: height)
        let scaledHeatmap = scaledImage(heatmapImage, from: heatmapImage.extent, to: outputRect)
        context.render(
            scaledHeatmap,
            to: heatmapTexture,
            commandBuffer: commandBuffer,
            bounds: outputRect,
            colorSpace: colorSpace
        )

        var uniforms = HeatmapFrameOffsetUniforms(
            outputWidth: UInt32(width),
            outputHeight: UInt32(height),
            cellWidth: UInt32(max(1, Int(snapshot.cellSize.width.rounded()))),
            cellHeight: UInt32(max(1, Int(snapshot.cellSize.height.rounded()))),
            columns: UInt32(max(1, snapshot.columns)),
            rows: UInt32(max(1, snapshot.rows)),
            capacity: UInt32(max(1, snapshot.capacity)),
            frameCount: UInt32(max(0, snapshot.frameCount)),
            frameZeroIndex: UInt32(max(0, snapshot.frameZeroIndex)),
            maxFrameOffset: UInt32(max(0, maxFrameOffset)),
            padding0: 0,
            padding1: 0,
            padding2: 0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(snapshot.texture, index: 0)
        encoder.setTexture(heatmapTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<HeatmapFrameOffsetUniforms>.stride, index: 0)

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
        return outputImage.cropped(to: outputRect)
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

    private func ensureHeatmapTexture(width: Int, height: Int) -> Bool {
        if
            let heatmapTexture,
            heatmapTexture.width == width,
            heatmapTexture.height == height
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

        heatmapTexture = device.makeTexture(descriptor: descriptor)
        return heatmapTexture != nil
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
            let function = library.makeFunction(name: "heatmapFrameOffsetAtlasKernel"),
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

        struct HeatmapFrameOffsetUniforms {
            uint outputWidth;
            uint outputHeight;
            uint cellWidth;
            uint cellHeight;
            uint columns;
            uint rows;
            uint capacity;
            uint frameCount;
            uint frameZeroIndex;
            uint maxFrameOffset;
            uint padding0;
            uint padding1;
            uint padding2;
        };

        kernel void heatmapFrameOffsetAtlasKernel(
            texture2d<float, access::read> atlasTexture [[texture(0)]],
            texture2d<float, access::read> heatmapTexture [[texture(1)]],
            texture2d<float, access::write> outputTexture [[texture(2)]],
            constant HeatmapFrameOffsetUniforms& uniforms [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= uniforms.outputWidth || gid.y >= uniforms.outputHeight) {
                return;
            }

            if (uniforms.frameCount == 0 || uniforms.columns == 0 || uniforms.rows == 0) {
                outputTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
                return;
            }

            float2 outSize = float2(float(uniforms.outputWidth), float(uniforms.outputHeight));
            float2 uv = (float2(gid) + 0.5f) / outSize;

            uint heatmapWidth = heatmapTexture.get_width();
            uint heatmapHeight = heatmapTexture.get_height();
            uint heatX = min(uint(floor(uv.x * float(heatmapWidth))), heatmapWidth - 1);
            uint heatY = min(uint(floor(uv.y * float(heatmapHeight))), heatmapHeight - 1);
            float4 heatColor = heatmapTexture.read(uint2(heatX, heatY));

            float normalized = clamp(heatColor.r, 0.0f, 1.0f);
            uint availableMax = uniforms.frameCount > 0 ? uniforms.frameCount - 1 : 0;
            uint clampedMaxOffset = min(uniforms.maxFrameOffset, availableMax);
            float offsetFloat = normalized * float(clampedMaxOffset);
            uint offsetLow = uint(floor(offsetFloat));
            uint offsetHigh = min(offsetLow + 1, clampedMaxOffset);
            float offsetBlend = fract(offsetFloat);

            uint wrappedLow = uniforms.capacity > 0 ? (offsetLow % uniforms.capacity) : 0;
            uint absoluteIndexLow = (uniforms.frameZeroIndex + uniforms.capacity - wrappedLow) % uniforms.capacity;
            uint colLow = absoluteIndexLow % uniforms.columns;
            uint rowLow = absoluteIndexLow / uniforms.columns;

            uint cellX = min(uint(floor(uv.x * float(uniforms.cellWidth))), uniforms.cellWidth - 1);
            uint cellY = min(uint(floor(uv.y * float(uniforms.cellHeight))), uniforms.cellHeight - 1);

            uint atlasXLow = colLow * uniforms.cellWidth + cellX;
            uint atlasYLow = rowLow * uniforms.cellHeight + cellY;
            float4 colorLow = atlasTexture.read(uint2(atlasXLow, atlasYLow));

            if (offsetHigh == offsetLow) {
                outputTexture.write(colorLow, gid);
                return;
            }

            uint wrappedHigh = uniforms.capacity > 0 ? (offsetHigh % uniforms.capacity) : 0;
            uint absoluteIndexHigh = (uniforms.frameZeroIndex + uniforms.capacity - wrappedHigh) % uniforms.capacity;
            uint colHigh = absoluteIndexHigh % uniforms.columns;
            uint rowHigh = absoluteIndexHigh / uniforms.columns;
            uint atlasXHigh = colHigh * uniforms.cellWidth + cellX;
            uint atlasYHigh = rowHigh * uniforms.cellHeight + cellY;
            float4 colorHigh = atlasTexture.read(uint2(atlasXHigh, atlasYHigh));

            outputTexture.write(mix(colorLow, colorHigh, offsetBlend), gid);
        }
        """

        guard
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "heatmapFrameOffsetAtlasKernel"),
            let pipeline = try? device.makeComputePipelineState(function: function)
        else {
            return nil
        }

        return pipeline
    }

    private func scaledImage(_ image: CIImage, from sourceRect: CGRect, to destRect: CGRect) -> CIImage {
        let movedToOrigin = image.transformed(
            by: CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )
        let sx = destRect.width / sourceRect.width
        let sy = destRect.height / sourceRect.height
        return movedToOrigin
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: destRect.minX, y: destRect.minY))
            .cropped(to: destRect)
    }
}
