import CoreGraphics
import CoreImage
import Foundation
import Metal
import Dispatch

/// Metal-only atlas consumer that generates a per-pixel temporal offset from
/// a Perlin-noise-like flow field and samples that frame from the atlas.
public final class PerlinFlowFieldAtlasConsumer {
    public var noiseScale: Float
    public var flowSpeed: Float
    public var maxFrameOffset: Int

    private struct FlowFieldUniforms {
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
        var noiseScale: Float
        var flowSpeed: Float
        var time: Float
        var padding: Float
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
        noiseScale: Float = 8.0,
        flowSpeed: Float = 0.18,
        maxFrameOffset: Int = 24,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) {
        self.noiseScale = noiseScale
        self.flowSpeed = flowSpeed
        self.maxFrameOffset = max(0, maxFrameOffset)
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
    }

    public func render(
        snapshot: TemporalTextureAtlasSnapshot,
        outputSize: CGSize,
        timeSeconds: Double
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

        var uniforms = FlowFieldUniforms(
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
            noiseScale: max(0.001, noiseScale),
            flowSpeed: flowSpeed,
            time: Float(timeSeconds),
            padding: 0
        )

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(snapshot.texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<FlowFieldUniforms>.stride, index: 0)

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
            let function = library.makeFunction(name: "perlinFlowFieldAtlasKernel"),
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

        struct FlowFieldUniforms {
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
            float noiseScale;
            float flowSpeed;
            float time;
            float padding;
        };

        inline float2 fade2(float2 t) {
            return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
        }

        inline float hash21(float2 p) {
            return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f);
        }

        inline float2 grad2(float2 cell) {
            float angle = hash21(cell) * 6.283185307f;
            return float2(cos(angle), sin(angle));
        }

        inline float perlin2d(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);

            float2 g00 = grad2(i + float2(0.0f, 0.0f));
            float2 g10 = grad2(i + float2(1.0f, 0.0f));
            float2 g01 = grad2(i + float2(0.0f, 1.0f));
            float2 g11 = grad2(i + float2(1.0f, 1.0f));

            float n00 = dot(g00, f - float2(0.0f, 0.0f));
            float n10 = dot(g10, f - float2(1.0f, 0.0f));
            float n01 = dot(g01, f - float2(0.0f, 1.0f));
            float n11 = dot(g11, f - float2(1.0f, 1.0f));

            float2 u = fade2(f);
            float nx0 = mix(n00, n10, u.x);
            float nx1 = mix(n01, n11, u.x);
            return mix(nx0, nx1, u.y);
        }

        inline float fbm2d(float2 p) {
            float sum = 0.0f;
            float amplitude = 0.5f;
            float amplitudeSum = 0.0f;
            float2 point = p;

            for (uint octave = 0; octave < 4; octave++) {
                sum += perlin2d(point) * amplitude;
                amplitudeSum += amplitude;
                point *= 2.0f;
                amplitude *= 0.5f;
            }

            return amplitudeSum > 0.0f ? (sum / amplitudeSum) : 0.0f;
        }

        kernel void perlinFlowFieldAtlasKernel(
            texture2d<float, access::read> atlasTexture [[texture(0)]],
            texture2d<float, access::write> outputTexture [[texture(1)]],
            constant FlowFieldUniforms& uniforms [[buffer(0)]],
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

            float2 flow = float2(uniforms.time * uniforms.flowSpeed, uniforms.time * uniforms.flowSpeed * 0.73f);
            float noise = fbm2d(uv * uniforms.noiseScale + flow);
            float normalized = clamp(noise * 0.5f + 0.5f, 0.0f, 1.0f);
            float biased = normalized * normalized;

            uint availableMax = uniforms.frameCount > 0 ? uniforms.frameCount - 1 : 0;
            uint clampedMaxOffset = min(uniforms.maxFrameOffset, availableMax);
            float offsetFloat = biased * float(clampedMaxOffset);
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
            let function = library.makeFunction(name: "perlinFlowFieldAtlasKernel"),
            let pipeline = try? device.makeComputePipelineState(function: function)
        else {
            return nil
        }
        return pipeline
    }
}
