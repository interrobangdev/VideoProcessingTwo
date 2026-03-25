import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Metal

/// Stateful temporal effect:
/// 1) writes incoming frames into a persistent atlas ring buffer,
/// 2) samples per-pixel frame offsets from a Perlin flow field in Metal.
public final class PerlinFlowFieldAtlasFilter: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    /// Maximum frame offset requested by the flow field (clamped to available history).
    public var maxFrameOffset: Int
    /// Spatial frequency of the flow field.
    public var noiseScale: Double
    /// Temporal movement speed of the flow field.
    public var flowSpeed: Double

    public var inputFrameSize: CGSize {
        didSet { writer.inputFrameSize = inputFrameSize }
    }

    public var maxAtlasDimension: Int {
        didSet { writer.maxAtlasDimension = max(1024, maxAtlasDimension) }
    }

    private let lock = NSLock()
    private let writer: MetalTemporalTextureAtlasWriter
    private let consumer: PerlinFlowFieldAtlasConsumer

    public init(
        maxFrameOffset: Int = 24,
        noiseScale: Double = 8.0,
        flowSpeed: Double = 0.18,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        let sharedDevice = MTLCreateSystemDefaultDevice()
        self.maxFrameOffset = max(0, maxFrameOffset)
        self.noiseScale = max(0.001, noiseScale)
        self.flowSpeed = flowSpeed
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.writer = MetalTemporalTextureAtlasWriter(
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension,
            device: sharedDevice
        )
        self.consumer = PerlinFlowFieldAtlasConsumer(
            noiseScale: Float(noiseScale),
            flowSpeed: Float(flowSpeed),
            maxFrameOffset: maxFrameOffset,
            device: sharedDevice
        )
    }

    public func resetState() {
        lock.lock()
        defer { lock.unlock() }
        writer.reset()
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let value = value as? Double {
                maxFrameOffset = max(0, Int(value.rounded()))
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

        writer.inputFrameSize = inputFrameSize
        writer.maxAtlasDimension = maxAtlasDimension
        guard let snapshot = writer.appendFrame(image) else {
            return image
        }

        consumer.maxFrameOffset = maxFrameOffset
        consumer.noiseScale = Float(max(0.001, noiseScale))
        consumer.flowSpeed = Float(flowSpeed)

        let time = CMTimeGetSeconds(compositionTime ?? sceneTime ?? sourceTime ?? .zero)
        guard let output = consumer.render(
            snapshot: snapshot,
            outputSize: image.extent.size,
            timeSeconds: time.isFinite ? time : 0.0
        ) else {
            return image
        }

        if image.extent.origin == .zero {
            return output
        }
        return output.transformed(
            by: CGAffineTransform(translationX: image.extent.origin.x, y: image.extent.origin.y)
        )
    }
}
