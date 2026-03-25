import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Metal

/// Stateful temporal effect that blends past atlas frames while tinting each
/// sample with a repeating color palette (RGB, 6-way spectrum, 9-way spectrum, etc.).
public final class TemporalColorSplitAtlasFilter: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    /// Number of temporal samples to blend together.
    public var frameCount: Int

    /// Distance between temporal samples in frames (`1` = consecutive frames).
    public var frameSpacing: Int

    /// Number of palette components to split the samples across.
    public var componentCount: Int

    public var inputFrameSize: CGSize {
        didSet { writer.inputFrameSize = inputFrameSize }
    }

    public var maxAtlasDimension: Int {
        didSet { writer.maxAtlasDimension = max(1024, maxAtlasDimension) }
    }

    private let lock = NSLock()
    private let writer: MetalTemporalTextureAtlasWriter
    private let consumer: TemporalColorSplitAtlasConsumer

    public init(
        frameCount: Int = 5,
        frameSpacing: Int = 1,
        componentCount: Int = 3,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        let sharedDevice = MTLCreateSystemDefaultDevice()
        self.frameCount = max(1, frameCount)
        self.frameSpacing = max(1, frameSpacing)
        self.componentCount = max(1, componentCount)
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.writer = MetalTemporalTextureAtlasWriter(
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension,
            device: sharedDevice
        )
        self.consumer = TemporalColorSplitAtlasConsumer(
            frameCount: frameCount,
            frameSpacing: frameSpacing,
            componentCount: componentCount,
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
        case .componentCount:
            if let value = value as? Double {
                componentCount = max(1, Int(value.rounded()))
            } else if let value = value as? Int {
                componentCount = max(1, value)
            }
        case .intensity:
            if let value = value as? Double {
                frameCount = max(1, Int(value.rounded()))
            }
        case .radius:
            if let value = value as? Double {
                frameSpacing = max(1, Int(value.rounded()))
            }
        case .mix:
            if let value = value as? Double {
                componentCount = max(1, Int(value.rounded()))
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
        consumer.componentCount = max(1, componentCount)

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
