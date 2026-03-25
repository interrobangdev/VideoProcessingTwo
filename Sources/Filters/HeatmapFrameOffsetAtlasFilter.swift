import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Metal

/// Stateful temporal effect:
/// 1) writes incoming frames into a persistent atlas ring buffer,
/// 2) samples per-pixel frame offsets from a supplied heatmap image's red channel.
public final class HeatmapFrameOffsetAtlasFilter: StatefulFilter, MultiInputFilter {
    public static let heatmapInputKey = "heatmap"

    public var filterAnimators: [FilterAnimator]
    public var additionalInputs: [String: CIImage] = [:]

    /// Maximum frame offset requested by the heatmap (clamped to available history).
    public var maxFrameOffset: Int

    public var heatmapImage: CIImage? {
        get { inputImage(forKey: Self.heatmapInputKey) }
        set { setInputImage(newValue, forKey: Self.heatmapInputKey) }
    }

    public var inputFrameSize: CGSize {
        didSet { writer.inputFrameSize = inputFrameSize }
    }

    public var maxAtlasDimension: Int {
        didSet { writer.maxAtlasDimension = max(1024, maxAtlasDimension) }
    }

    private let lock = NSLock()
    private let writer: MetalTemporalTextureAtlasWriter
    private let consumer: HeatmapFrameOffsetAtlasConsumer

    public init(
        maxFrameOffset: Int = 24,
        heatmapImage: CIImage? = nil,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        let sharedDevice = MTLCreateSystemDefaultDevice()
        self.maxFrameOffset = max(0, maxFrameOffset)
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.writer = MetalTemporalTextureAtlasWriter(
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension,
            device: sharedDevice
        )
        self.consumer = HeatmapFrameOffsetAtlasConsumer(
            maxFrameOffset: maxFrameOffset,
            device: sharedDevice
        )

        if let heatmapImage {
            self.additionalInputs[Self.heatmapInputKey] = heatmapImage
        }
    }

    public func setHeatmapImage(_ image: CIImage?) {
        heatmapImage = image
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

        guard let heatmapImage else {
            return image
        }

        writer.inputFrameSize = inputFrameSize
        writer.maxAtlasDimension = maxAtlasDimension
        guard let snapshot = writer.appendFrame(image) else {
            return image
        }

        consumer.maxFrameOffset = maxFrameOffset

        guard let output = consumer.render(
            snapshot: snapshot,
            outputSize: image.extent.size,
            heatmapImage: heatmapImage
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
