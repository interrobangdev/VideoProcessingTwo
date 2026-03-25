import CoreGraphics
import CoreImage
import Metal
import Foundation
import Dispatch

public struct TemporalTextureAtlasSnapshot {
    public let texture: MTLTexture
    public let textureSize: CGSize
    public let cellSize: CGSize
    public let columns: Int
    public let rows: Int
    public let capacity: Int
    public let frameCount: Int
    /// Absolute ring index of the newest frame (`index 0` for readback).
    public let frameZeroIndex: Int
}

public final class MetalTemporalTextureAtlasWriter {
    public var inputFrameSize: CGSize
    public var maxAtlasDimension: Int

    private struct AtlasWriteUniforms {
        var destX: UInt32
        var destY: UInt32
        var cellWidth: UInt32
        var cellHeight: UInt32
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
    private var detectedMaxTextureDimension: Int?

    private var pipeline: MTLComputePipelineState?

    private var atlasTexture: MTLTexture?
    private var stagingTexture: MTLTexture?

    private var cellWidth: Int = 1024
    private var cellHeight: Int = 1024
    private var columns: Int = 1
    private var rows: Int = 1
    private var capacity: Int = 1

    private var writeIndex: Int = 0
    private var frameCount: Int = 0
    private var lastWrittenIndex: Int = 0

    public init(
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) {
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
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

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        frameCount = 0
        lastWrittenIndex = 0
    }

    @discardableResult
    public func appendFrame(_ image: CIImage) -> TemporalTextureAtlasSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        guard ensureResources() else {
            return nil
        }
        guard
            let context,
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let pipeline,
            let atlasTexture,
            let stagingTexture
        else {
            return nil
        }

        let cellRect = CGRect(origin: .zero, size: CGSize(width: cellWidth, height: cellHeight))
        let scaledInput = scaledImage(image, from: image.extent, to: cellRect)
        context.render(
            scaledInput,
            to: stagingTexture,
            commandBuffer: commandBuffer,
            bounds: cellRect,
            colorSpace: colorSpace
        )

        let destination = destinationOrigin(for: writeIndex)
        var uniforms = AtlasWriteUniforms(
            destX: UInt32(destination.x),
            destY: UInt32(destination.y),
            cellWidth: UInt32(cellWidth),
            cellHeight: UInt32(cellHeight)
        )

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        computeEncoder.setComputePipelineState(pipeline)
        computeEncoder.setTexture(stagingTexture, index: 0)
        computeEncoder.setTexture(atlasTexture, index: 1)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<AtlasWriteUniforms>.stride, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: cellWidth, height: cellHeight, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status != .completed {
            let message = commandBuffer.error?.localizedDescription ?? "unknown command buffer failure"
            return nil
        }

        lastWrittenIndex = writeIndex
        writeIndex = (writeIndex + 1) % capacity
        frameCount = min(frameCount + 1, capacity)

        return TemporalTextureAtlasSnapshot(
            texture: atlasTexture,
            textureSize: CGSize(width: atlasTexture.width, height: atlasTexture.height),
            cellSize: CGSize(width: cellWidth, height: cellHeight),
            columns: columns,
            rows: rows,
            capacity: capacity,
            frameCount: frameCount,
            frameZeroIndex: lastWrittenIndex
        )
    }

    private func ensureResources() -> Bool {
        let requestedWidth = max(1, Int(inputFrameSize.width.rounded()))
        let requestedHeight = max(1, Int(inputFrameSize.height.rounded()))

        if
            atlasTexture != nil,
            stagingTexture != nil,
            pipeline != nil,
            requestedWidth == cellWidth,
            requestedHeight == cellHeight
        {
            return true
        }

        guard let device else {
            return false
        }

        if pipeline == nil {
            pipeline = Self.makePipeline(device: device)
            if pipeline == nil {
                return false
            }
        }

        let maxDimension = max(1, min(detectMaxTextureDimension(device: device), maxAtlasDimension))
        let cols = max(1, maxDimension / requestedWidth)
        let rowCount = max(1, maxDimension / requestedHeight)
        let atlasWidth = cols * requestedWidth
        let atlasHeight = rowCount * requestedHeight

        let atlasDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        atlasDescriptor.usage = MTLTextureUsage.shaderRead.union(.shaderWrite)
        atlasDescriptor.storageMode = MTLStorageMode.private

        guard let atlas = device.makeTexture(descriptor: atlasDescriptor) else {
            return false
        }

        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: requestedWidth,
            height: requestedHeight,
            mipmapped: false
        )
        stagingDescriptor.usage = MTLTextureUsage.renderTarget
            .union(.shaderRead)
            .union(.shaderWrite)
        stagingDescriptor.storageMode = MTLStorageMode.private

        guard let staging = device.makeTexture(descriptor: stagingDescriptor) else {
            return false
        }

        atlasTexture = atlas
        stagingTexture = staging
        cellWidth = requestedWidth
        cellHeight = requestedHeight
        columns = cols
        rows = rowCount
        capacity = max(1, cols * rowCount)
        writeIndex = 0
        frameCount = 0
        lastWrittenIndex = 0
        return true
    }

    private func destinationOrigin(for index: Int) -> (x: Int, y: Int) {
        let col = index % columns
        let row = index / columns
        return (x: col * cellWidth, y: row * cellHeight)
    }

    private func detectMaxTextureDimension(device: MTLDevice) -> Int {
        if let detectedMaxTextureDimension {
            return detectedMaxTextureDimension
        }

        let candidates = [32768, 16384, 8192, 4096, 2048, 1024].filter { $0 <= maxAtlasDimension }
        for size in candidates {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: size,
                height: size,
                mipmapped: false
            )
            descriptor.usage = MTLTextureUsage.shaderRead.union(.shaderWrite)
            descriptor.storageMode = MTLStorageMode.private
            if device.makeTexture(descriptor: descriptor) != nil {
                detectedMaxTextureDimension = size
                return size
            }
        }

        detectedMaxTextureDimension = 1024
        return 1024
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
            let function = library.makeFunction(name: "atlasWriteKernel"),
            let compiled = try? device.makeComputePipelineState(function: function)
        {
            pipeline = compiled
        } else {
            pipeline = makePipelineFromSource(device: device)
        }
        guard let pipeline else {
            return nil
        }

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

        struct AtlasWriteUniforms {
            uint destX;
            uint destY;
            uint cellWidth;
            uint cellHeight;
        };

        kernel void atlasWriteKernel(
            texture2d<float, access::read> sourceTexture [[texture(0)]],
            texture2d<float, access::write> atlasTexture [[texture(1)]],
            constant AtlasWriteUniforms& uniforms [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= uniforms.cellWidth || gid.y >= uniforms.cellHeight) {
                return;
            }
            float4 color = sourceTexture.read(gid);
            uint2 destCoord = uint2(uniforms.destX + gid.x, uniforms.destY + gid.y);
            atlasTexture.write(color, destCoord);
        }
        """

        guard
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "atlasWriteKernel"),
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
