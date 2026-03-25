import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Metal

/// Stateful temporal effect that averages a series of atlas samples from newest
/// backward in time using a fixed spacing between samples.
public final class TemporalFadeAtlasFilter: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    /// Number of temporal samples to average together.
    public var frameCount: Int

    /// Distance between temporal samples in frames (`1` = consecutive frames).
    public var frameSpacing: Int

    public var inputFrameSize: CGSize {
        didSet { writer.inputFrameSize = inputFrameSize }
    }

    public var maxAtlasDimension: Int {
        didSet { writer.maxAtlasDimension = max(1024, maxAtlasDimension) }
    }

    private let lock = NSLock()
    private let writer: MetalTemporalTextureAtlasWriter
    private let consumer: TemporalFadeAtlasConsumer

    public init(
        frameCount: Int = 5,
        frameSpacing: Int = 1,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        let sharedDevice = MTLCreateSystemDefaultDevice()
        self.frameCount = max(1, frameCount)
        self.frameSpacing = max(1, frameSpacing)
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.writer = MetalTemporalTextureAtlasWriter(
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension,
            device: sharedDevice
        )
        self.consumer = TemporalFadeAtlasConsumer(
            frameCount: frameCount,
            frameSpacing: frameSpacing,
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
        case .frameCount:
            if let value = value as? Double {
                frameCount = max(1, Int(value.rounded()))
            } else if let value = value as? Int {
                frameCount = max(1, value)
            }
        case .frameSpacing:
            if let value = value as? Double {
                frameSpacing = max(1, Int(value.rounded()))
            } else if let value = value as? Int {
                frameSpacing = max(1, value)
            }
        case .intensity:
            if let value = value as? Double {
                frameCount = max(1, Int(value.rounded()))
            }
        case .radius:
            if let value = value as? Double {
                frameSpacing = max(1, Int(value.rounded()))
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

        consumer.frameCount = max(1, frameCount)
        consumer.frameSpacing = max(1, frameSpacing)

        guard let output = consumer.render(
            snapshot: snapshot,
            outputSize: image.extent.size
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
