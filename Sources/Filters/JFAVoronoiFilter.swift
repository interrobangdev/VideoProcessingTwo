import CoreGraphics
import CoreImage
import CoreMedia
import Dispatch
import Foundation
import Metal
import simd

/// Voronoi filter powered by multi-pass Jump Flood Algorithm (JFA).
/// Centroids are provided by a generic particle generator.
public final class JFAVoronoiFilter: StatefulFilter {
    private static let requiredKernelNames = [
        "jfaClearSeedKernel",
        "jfaSplatParticlesKernel",
        "jfaJumpFloodKernel",
        "jfaResolveVoronoiKernel",
    ]

    public var filterAnimators: [FilterAnimator]

    public var particleCount: Int {
        didSet { particleCount = max(1, particleCount) }
    }

    /// 0...1 blend between source and Voronoi output.
    public var intensity: Double {
        didSet { intensity = clamped(intensity, min: 0.0, max: 1.0) }
    }

    /// 0...1 amount of boundary darkening.
    public var edgeIntensity: Double {
        didSet { edgeIntensity = clamped(edgeIntensity, min: 0.0, max: 1.0) }
    }

    /// 0...1 per-cell color tint amount.
    public var colorVariation: Double {
        didSet { colorVariation = clamped(colorVariation, min: 0.0, max: 1.0) }
    }

    public var particleVelocity: Double {
        didSet {
            particleVelocity = max(0.0, particleVelocity)
            syncAnimatedGeneratorTuning()
        }
    }

    public var particleOrbitAmplitude: Double {
        didSet {
            particleOrbitAmplitude = max(0.0, particleOrbitAmplitude)
            syncAnimatedGeneratorTuning()
        }
    }

    public var particleDriftSpeed: Double {
        didSet {
            particleDriftSpeed = max(0.0, particleDriftSpeed)
            syncAnimatedGeneratorTuning()
        }
    }

    public var particleJitter: Double {
        didSet {
            particleJitter = max(0.0, particleJitter)
            syncAnimatedGeneratorTuning()
        }
    }

    public var particleGenerator: any ParticleGenerator {
        didSet { syncAnimatedGeneratorTuning() }
    }

    private struct JFASplatUniforms {
        var particleCount: UInt32
        var padding0: UInt32 = 0
        var padding1: UInt32 = 0
        var padding2: UInt32 = 0
    }

    private struct JFAJumpUniforms {
        var width: UInt32
        var height: UInt32
        var step: UInt32
        var padding: UInt32 = 0
    }

    private struct JFAResolveUniforms {
        var width: UInt32
        var height: UInt32
        var blend: Float
        var edgeIntensity: Float
        var colorVariation: Float
        var padding: Float = 0
    }

    private let lock = NSLock()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext

    private var clearSeedPipeline: MTLComputePipelineState?
    private var splatPipeline: MTLComputePipelineState?
    private var jumpFloodPipeline: MTLComputePipelineState?
    private var resolvePipeline: MTLComputePipelineState?

    private var sourceTexture: MTLTexture?
    private var seedTexture: MTLTexture?
    private var pingTexture: MTLTexture?
    private var pongTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    private var outputImage: CIImage?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    private var particleBuffer: MTLBuffer?

    public init(
        particleCount: Int = 160,
        intensity: Double = 1.0,
        edgeIntensity: Double = 0.8,
        colorVariation: Double = 0.35,
        particleVelocity: Double = 0.10,
        particleOrbitAmplitude: Double = 0.07,
        particleDriftSpeed: Double = 0.45,
        particleJitter: Double = 0.25,
        particleGenerator: (any ParticleGenerator)? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.particleCount = max(1, particleCount)
        self.intensity = clamped(intensity, min: 0.0, max: 1.0)
        self.edgeIntensity = clamped(edgeIntensity, min: 0.0, max: 1.0)
        self.colorVariation = clamped(colorVariation, min: 0.0, max: 1.0)
        self.particleVelocity = max(0.0, particleVelocity)
        self.particleOrbitAmplitude = max(0.0, particleOrbitAmplitude)
        self.particleDriftSpeed = max(0.0, particleDriftSpeed)
        self.particleJitter = max(0.0, particleJitter)
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

        if let particleGenerator {
            self.particleGenerator = particleGenerator
        } else {
            self.particleGenerator = AnimatedParticleGenerator(
                velocity: Float(self.particleVelocity),
                orbitAmplitude: Float(self.particleOrbitAmplitude),
                orbitSpeed: Float(self.particleDriftSpeed),
                jitterAmount: Float(self.particleJitter)
            )
        }
        syncAnimatedGeneratorTuning()
    }

    public func resetState() {
        lock.lock()
        defer { lock.unlock() }

        sourceTexture = nil
        seedTexture = nil
        pingTexture = nil
        pongTexture = nil
        outputTexture = nil
        outputImage = nil
        particleBuffer = nil
        textureWidth = 0
        textureHeight = 0
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let value = value as? Double { intensity = value }
        case .filterStrength:
            if let value = value as? Double { edgeIntensity = value }
        case .hue:
            if let value = value as? Double { colorVariation = value }
        case .scale:
            if let value = value as? Double {
                particleCount = max(1, Int(value.rounded()))
            }
        default:
            break
        }
    }

    public func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }

        guard ensurePipelines() else {
            return image
        }
        guard ensureTextures(for: image.extent.size) else {
            return image
        }
        guard let commandQueue else {
            return image
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return image
        }
        guard
            let sourceTexture,
            let seedTexture,
            let pingTexture,
            let pongTexture,
            let outputTexture
        else {
            return image
        }

        let outputRect = CGRect(origin: .zero, size: CGSize(width: textureWidth, height: textureHeight))
        let normalizedInput = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
            .cropped(to: outputRect)
        context.render(
            normalizedInput,
            to: sourceTexture,
            commandBuffer: commandBuffer,
            bounds: outputRect,
            colorSpace: colorSpace
        )

        let time = CMTimeGetSeconds(compositionTime ?? sceneTime ?? sourceTime ?? .zero)
        let particlePositions = particleGenerator.particlePositions(
            at: time.isFinite ? time : 0.0,
            count: particleCount
        )
        let uploadedParticleCount = uploadParticles(particlePositions)

        guard
            encodeClearSeeds(commandBuffer: commandBuffer, texture: seedTexture),
            encodeSplatParticles(
                commandBuffer: commandBuffer,
                texture: seedTexture,
                particleCount: uploadedParticleCount
            )
        else {
            return image
        }

        var currentSource = seedTexture
        var currentDestination = pingTexture
        let jumps = jumpSteps(for: max(textureWidth, textureHeight))

        for jump in jumps {
            guard encodeJumpFlood(
                commandBuffer: commandBuffer,
                sourceTexture: currentSource,
                destinationTexture: currentDestination,
                jumpStep: jump
            ) else {
                return image
            }
            swap(&currentSource, &currentDestination)
        }

        guard encodeResolve(
            commandBuffer: commandBuffer,
            sourceTexture: sourceTexture,
            resolvedSeedTexture: currentSource,
            outputTexture: outputTexture
        ) else {
            return image
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status != .completed {
            let message = commandBuffer.error?.localizedDescription ?? "unknown command buffer failure"
            return image
        }

        guard let outputImage else {
            return image
        }

        let cropped = outputImage.cropped(to: outputRect)
        if image.extent.origin == .zero {
            return cropped
        }
        return cropped.transformed(
            by: CGAffineTransform(translationX: image.extent.origin.x, y: image.extent.origin.y)
        )
    }

    private func ensurePipelines() -> Bool {
        if clearSeedPipeline != nil && splatPipeline != nil && jumpFloodPipeline != nil && resolvePipeline != nil {
            return true
        }
        guard let device else { return false }
        guard let library = makeLibrary(device: device) else { return false }

        clearSeedPipeline = makePipeline(device: device, library: library, functionName: "jfaClearSeedKernel")
        splatPipeline = makePipeline(device: device, library: library, functionName: "jfaSplatParticlesKernel")
        jumpFloodPipeline = makePipeline(device: device, library: library, functionName: "jfaJumpFloodKernel")
        resolvePipeline = makePipeline(device: device, library: library, functionName: "jfaResolveVoronoiKernel")

        return clearSeedPipeline != nil &&
            splatPipeline != nil &&
            jumpFloodPipeline != nil &&
            resolvePipeline != nil
    }

    private func ensureTextures(for size: CGSize) -> Bool {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))

        if
            width == textureWidth,
            height == textureHeight,
            sourceTexture != nil,
            seedTexture != nil,
            pingTexture != nil,
            pongTexture != nil,
            outputTexture != nil,
            outputImage != nil
        {
            return true
        }

        guard let device else { return false }

        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        sourceDescriptor.usage = MTLTextureUsage.shaderRead.union(.renderTarget)
        sourceDescriptor.storageMode = .private

        let seedDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        seedDescriptor.usage = MTLTextureUsage.shaderRead.union(.shaderWrite)
        seedDescriptor.storageMode = .private

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = MTLTextureUsage.shaderRead.union(.shaderWrite)
        outputDescriptor.storageMode = .private

        guard
            let sourceTexture = device.makeTexture(descriptor: sourceDescriptor),
            let seedTexture = device.makeTexture(descriptor: seedDescriptor),
            let pingTexture = device.makeTexture(descriptor: seedDescriptor),
            let pongTexture = device.makeTexture(descriptor: seedDescriptor),
            let outputTexture = device.makeTexture(descriptor: outputDescriptor)
        else {
            return false
        }

        self.sourceTexture = sourceTexture
        self.seedTexture = seedTexture
        self.pingTexture = pingTexture
        self.pongTexture = pongTexture
        self.outputTexture = outputTexture
        self.outputImage = CIImage(
            mtlTexture: outputTexture,
            options: [CIImageOption.colorSpace: colorSpace]
        )
        self.textureWidth = width
        self.textureHeight = height
        return self.outputImage != nil
    }

    private func encodeClearSeeds(commandBuffer: MTLCommandBuffer, texture: MTLTexture) -> Bool {
        guard let clearSeedPipeline, let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(clearSeedPipeline)
        encoder.setTexture(texture, index: 0)
        dispatch2D(encoder: encoder, width: textureWidth, height: textureHeight)
        encoder.endEncoding()
        return true
    }

    private func encodeSplatParticles(
        commandBuffer: MTLCommandBuffer,
        texture: MTLTexture,
        particleCount: Int
    ) -> Bool {
        guard particleCount > 0 else { return true }
        guard let splatPipeline, let particleBuffer, let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }

        var uniforms = JFASplatUniforms(particleCount: UInt32(particleCount))
        encoder.setComputePipelineState(splatPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<JFASplatUniforms>.stride, index: 1)
        encoder.setTexture(texture, index: 0)

        let threadsPerGrid = MTLSize(width: particleCount, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(
            width: max(1, min(splatPipeline.threadExecutionWidth, particleCount)),
            height: 1,
            depth: 1
        )
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        return true
    }

    private func encodeJumpFlood(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        jumpStep: Int
    ) -> Bool {
        guard let jumpFloodPipeline, let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }

        var uniforms = JFAJumpUniforms(
            width: UInt32(textureWidth),
            height: UInt32(textureHeight),
            step: UInt32(max(1, jumpStep))
        )

        encoder.setComputePipelineState(jumpFloodPipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<JFAJumpUniforms>.stride, index: 0)
        dispatch2D(encoder: encoder, width: textureWidth, height: textureHeight)
        encoder.endEncoding()
        return true
    }

    private func encodeResolve(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        resolvedSeedTexture: MTLTexture,
        outputTexture: MTLTexture
    ) -> Bool {
        guard let resolvePipeline, let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }

        var uniforms = JFAResolveUniforms(
            width: UInt32(textureWidth),
            height: UInt32(textureHeight),
            blend: Float(intensity),
            edgeIntensity: Float(edgeIntensity),
            colorVariation: Float(colorVariation)
        )

        encoder.setComputePipelineState(resolvePipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(resolvedSeedTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<JFAResolveUniforms>.stride, index: 0)
        dispatch2D(encoder: encoder, width: textureWidth, height: textureHeight)
        encoder.endEncoding()
        return true
    }

    private func dispatch2D(encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    private func jumpSteps(for dimension: Int) -> [Int] {
        let maxDimension = max(1, dimension)
        var step = 1
        while step * 2 <= maxDimension {
            step *= 2
        }

        var steps: [Int] = []
        while step >= 1 {
            steps.append(step)
            if step == 1 {
                break
            }
            step /= 2
        }
        return steps
    }

    private func uploadParticles(_ particlePositions: [SIMD2<Float>]) -> Int {
        let count = max(0, min(particleCount, particlePositions.count))
        guard count > 0, let device else {
            return 0
        }

        let clampedPositions = particlePositions.prefix(count).map {
            SIMD2(
                clamped($0.x, min: 0.0, max: 0.999999),
                clamped($0.y, min: 0.0, max: 0.999999)
            )
        }
        let byteCount = clampedPositions.count * MemoryLayout<SIMD2<Float>>.stride

        if particleBuffer == nil || particleBuffer?.length ?? 0 < byteCount {
            particleBuffer = device.makeBuffer(length: max(byteCount, 1), options: .storageModeShared)
        }
        guard let particleBuffer else { return 0 }

        clampedPositions.withUnsafeBytes { rawBuffer in
            guard let sourceBase = rawBuffer.baseAddress else { return }
            memcpy(particleBuffer.contents(), sourceBase, rawBuffer.count)
        }
        return clampedPositions.count
    }

    private func syncAnimatedGeneratorTuning() {
        guard let generator = particleGenerator as? AnimatedParticleGenerator else { return }
        generator.velocity = Float(particleVelocity)
        generator.orbitAmplitude = Float(particleOrbitAmplitude)
        generator.orbitSpeed = Float(particleDriftSpeed)
        generator.jitterAmount = Float(particleJitter)
    }

    private func makeLibrary(device: MTLDevice) -> MTLLibrary? {
        if
            let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
            let data = try? Data(contentsOf: url),
            let library = try? device.makeLibrary(data: dispatchData(from: data)),
            libraryContainsRequiredKernels(library)
        {
            return library
        }
        if
            let library = try? device.makeDefaultLibrary(bundle: .module),
            libraryContainsRequiredKernels(library)
        {
            return library
        }
        if
            let sourceURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal", subdirectory: "Shaders"),
            let source = try? String(contentsOf: sourceURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            libraryContainsRequiredKernels(library)
        {
            return library
        }
        if
            let library = try? device.makeLibrary(source: Self.jfaFallbackMetalSource, options: nil),
            libraryContainsRequiredKernels(library)
        {
            return library
        }
        return nil
    }

    private func libraryContainsRequiredKernels(_ library: MTLLibrary) -> Bool {
        Self.requiredKernelNames.allSatisfy { library.makeFunction(name: $0) != nil }
    }

    private func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        functionName: String
    ) -> MTLComputePipelineState? {
        guard let function = library.makeFunction(name: functionName) else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }

    private func dispatchData(from data: Data) -> DispatchData {
        var result = DispatchData.empty
        data.withUnsafeBytes { rawBuffer in
            let typed = rawBuffer.bindMemory(to: UInt8.self)
            guard let base = typed.baseAddress else { return }
            result = DispatchData(bytes: UnsafeBufferPointer(start: base, count: typed.count))
        }
        return result
    }
}

private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    Swift.max(minValue, Swift.min(maxValue, value))
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(maxValue, value))
}

private extension JFAVoronoiFilter {
    static let jfaFallbackMetalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct JFASplatUniforms {
        uint particleCount;
        uint padding0;
        uint padding1;
        uint padding2;
    };

    struct JFAJumpUniforms {
        uint width;
        uint height;
        uint step;
        uint padding;
    };

    struct JFAResolveUniforms {
        uint width;
        uint height;
        float blend;
        float edgeIntensity;
        float colorVariation;
        float padding;
    };

    inline float hash11(float2 p) {
        return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f);
    }

    inline float3 seedTint(float2 seedUV) {
        float r = hash11(seedUV + float2(0.0f, 1.3f));
        float g = hash11(seedUV + float2(4.7f, 2.1f));
        float b = hash11(seedUV + float2(9.2f, 7.9f));
        return 0.82f + 0.36f * float3(r, g, b);
    }

    kernel void jfaClearSeedKernel(
        texture2d<float, access::write> seedTexture [[texture(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= seedTexture.get_width() || gid.y >= seedTexture.get_height()) {
            return;
        }
        seedTexture.write(float4(-1.0f, -1.0f, 0.0f, 0.0f), gid);
    }

    kernel void jfaSplatParticlesKernel(
        const device float2* particles [[buffer(0)]],
        constant JFASplatUniforms& uniforms [[buffer(1)]],
        texture2d<float, access::read_write> seedTexture [[texture(0)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= uniforms.particleCount) {
            return;
        }

        float2 uv = clamp(particles[gid], float2(0.0f), float2(0.999999f));
        uint width = seedTexture.get_width();
        uint height = seedTexture.get_height();

        uint2 pixel = uint2(
            min(uint(uv.x * float(width)), max(0u, width - 1)),
            min(uint(uv.y * float(height)), max(0u, height - 1))
        );
        seedTexture.write(float4(uv, 1.0f, 1.0f), pixel);
    }

    kernel void jfaJumpFloodKernel(
        texture2d<float, access::read> sourceSeedTexture [[texture(0)]],
        texture2d<float, access::write> destinationSeedTexture [[texture(1)]],
        constant JFAJumpUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
            return;
        }

        float2 uv = (float2(gid) + 0.5f) / float2(float(uniforms.width), float(uniforms.height));
        float4 bestSeed = sourceSeedTexture.read(gid);
        float bestDistance = 1e20f;

        if (bestSeed.z > 0.5f) {
            float2 diff = bestSeed.xy - uv;
            bestDistance = dot(diff, diff);
        }

        int jump = max(1, int(uniforms.step));
        for (int oy = -1; oy <= 1; oy++) {
            for (int ox = -1; ox <= 1; ox++) {
                int2 sampleCoord = int2(gid) + int2(ox, oy) * jump;
                if (
                    sampleCoord.x < 0 || sampleCoord.y < 0 ||
                    sampleCoord.x >= int(uniforms.width) || sampleCoord.y >= int(uniforms.height)
                ) {
                    continue;
                }

                float4 candidate = sourceSeedTexture.read(uint2(sampleCoord));
                if (candidate.z < 0.5f) {
                    continue;
                }

                float2 diff = candidate.xy - uv;
                float distanceSquared = dot(diff, diff);
                if (distanceSquared < bestDistance) {
                    bestDistance = distanceSquared;
                    bestSeed = candidate;
                }
            }
        }

        if (bestDistance >= 1e19f) {
            destinationSeedTexture.write(float4(-1.0f, -1.0f, 0.0f, 0.0f), gid);
        } else {
            destinationSeedTexture.write(bestSeed, gid);
        }
    }

    kernel void jfaResolveVoronoiKernel(
        texture2d<float, access::read> sourceTexture [[texture(0)]],
        texture2d<float, access::read> resolvedSeedTexture [[texture(1)]],
        texture2d<float, access::write> outputTexture [[texture(2)]],
        constant JFAResolveUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
            return;
        }

        float4 sourceColor = sourceTexture.read(gid);
        float4 seed = resolvedSeedTexture.read(gid);
        if (seed.z < 0.5f) {
            outputTexture.write(sourceColor, gid);
            return;
        }

        uint maxX = max(0u, uniforms.width - 1);
        uint maxY = max(0u, uniforms.height - 1);
        uint2 seedPixel = uint2(
            min(uint(seed.x * float(uniforms.width)), maxX),
            min(uint(seed.y * float(uniforms.height)), maxY)
        );

        float4 voronoiColor = sourceTexture.read(seedPixel);
        float3 tint = seedTint(seed.xy);
        float tintAmount = clamp(uniforms.colorVariation, 0.0f, 1.0f);
        voronoiColor.rgb = mix(voronoiColor.rgb, voronoiColor.rgb * tint, tintAmount);

        float edgeVotes = 0.0f;
        float edgeTotal = 0.0f;
        float epsilon = 1e-7f;

        if (gid.x > 0) {
            float4 neighbor = resolvedSeedTexture.read(uint2(gid.x - 1, gid.y));
            edgeTotal += 1.0f;
            if (neighbor.z > 0.5f) {
                float2 delta = neighbor.xy - seed.xy;
                if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
            } else {
                edgeVotes += 1.0f;
            }
        }
        if (gid.x < maxX) {
            float4 neighbor = resolvedSeedTexture.read(uint2(gid.x + 1, gid.y));
            edgeTotal += 1.0f;
            if (neighbor.z > 0.5f) {
                float2 delta = neighbor.xy - seed.xy;
                if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
            } else {
                edgeVotes += 1.0f;
            }
        }
        if (gid.y > 0) {
            float4 neighbor = resolvedSeedTexture.read(uint2(gid.x, gid.y - 1));
            edgeTotal += 1.0f;
            if (neighbor.z > 0.5f) {
                float2 delta = neighbor.xy - seed.xy;
                if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
            } else {
                edgeVotes += 1.0f;
            }
        }
        if (gid.y < maxY) {
            float4 neighbor = resolvedSeedTexture.read(uint2(gid.x, gid.y + 1));
            edgeTotal += 1.0f;
            if (neighbor.z > 0.5f) {
                float2 delta = neighbor.xy - seed.xy;
                if (dot(delta, delta) > epsilon) edgeVotes += 1.0f;
            } else {
                edgeVotes += 1.0f;
            }
        }

        float edge = edgeTotal > 0.0f ? (edgeVotes / edgeTotal) : 0.0f;
        float edgeAmount = clamp(uniforms.edgeIntensity, 0.0f, 1.0f);
        voronoiColor.rgb *= (1.0f - edge * edgeAmount);

        float blend = clamp(uniforms.blend, 0.0f, 1.0f);
        outputTexture.write(mix(sourceColor, voronoiColor, blend), gid);
    }
    """
}
