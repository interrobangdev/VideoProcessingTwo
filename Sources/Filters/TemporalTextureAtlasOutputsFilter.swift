import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Metal

/// Wrapper that composes a Metal atlas writer + atlas reader.
/// It can be used as a normal `Filter` (returns one image) and also exposes
/// multi-output results via `outputImages(...)`.
public final class TemporalTextureAtlasOutputsFilter: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    /// Relative frame offsets from newest frame (`0` = newest).
    public var frameOffsets: [Int]

    /// Which element from `frameOffsets` should be returned from `filterContent`.
    public var primaryOutputIndex: Int

    public var inputFrameSize: CGSize {
        didSet { writer.inputFrameSize = inputFrameSize }
    }

    public var maxAtlasDimension: Int {
        didSet { writer.maxAtlasDimension = max(1024, maxAtlasDimension) }
    }

    public private(set) var lastOutputImages: [CIImage] = []

    private let lock = NSLock()
    private let writer: MetalTemporalTextureAtlasWriter
    private let reader: TemporalTextureAtlasReader
    private let freezeContext: CIContext

    public init(
        frameOffsets: [Int] = [0],
        primaryOutputIndex: Int = 0,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.frameOffsets = frameOffsets.map { max(0, $0) }
        self.primaryOutputIndex = max(0, primaryOutputIndex)
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.writer = MetalTemporalTextureAtlasWriter(
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension
        )
        self.reader = TemporalTextureAtlasReader()
        if let device = MTLCreateSystemDefaultDevice() {
            self.freezeContext = CIContext(
                mtlDevice: device,
                options: [CIContextOption.cacheIntermediates: false]
            )
        } else {
            self.freezeContext = CIContext(options: [CIContextOption.cacheIntermediates: false])
        }
    }

    public func resetState() {
        lock.lock()
        defer { lock.unlock() }
        writer.reset()
        lastOutputImages.removeAll(keepingCapacity: false)
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let value = value as? Double {
                let offset = max(0, Int(value.rounded()))
                if frameOffsets.isEmpty {
                    frameOffsets = [offset]
                } else {
                    frameOffsets[0] = offset
                }
            }
        default:
            break
        }
    }

    public func outputImages(
        image: CIImage,
        sourceTime: CMTime? = nil,
        sceneTime: CMTime? = nil,
        compositionTime: CMTime? = nil
    ) -> [CIImage] {
        lock.lock()
        defer { lock.unlock() }

        writer.inputFrameSize = inputFrameSize
        writer.maxAtlasDimension = max(1024, maxAtlasDimension)

        guard let snapshot = writer.appendFrame(image) else {
            return [image]
        }

        let requestedOffsets = frameOffsets.isEmpty ? [0] : frameOffsets
        let clampedOffsets = requestedOffsets.map { max(0, $0) }
        let outputs = reader.images(
            from: snapshot,
            indices: clampedOffsets,
            outputSize: image.extent.size
        )
        let frozenOutputs = freeze(outputs, outputSize: image.extent.size)

        if frozenOutputs.isEmpty {
            lastOutputImages = [image]
            return lastOutputImages
        }

        if image.extent.origin == .zero {
            lastOutputImages = frozenOutputs
            return frozenOutputs
        }

        let translated = frozenOutputs.map {
            $0.transformed(by: CGAffineTransform(translationX: image.extent.origin.x, y: image.extent.origin.y))
        }
        lastOutputImages = translated
        return translated
    }

    public func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        let outputs = outputImages(
            image: image,
            sourceTime: sourceTime,
            sceneTime: sceneTime,
            compositionTime: compositionTime
        )

        guard !outputs.isEmpty else {
            return image
        }
        let index = min(max(0, primaryOutputIndex), outputs.count - 1)
        return outputs[index]
    }

    private func freeze(_ images: [CIImage], outputSize: CGSize) -> [CIImage] {
        guard outputSize.width > 0, outputSize.height > 0 else {
            return images
        }

        let targetRect = CGRect(origin: .zero, size: outputSize)
        return images.map { image in
            let cropped = image.cropped(to: targetRect)
            guard let cgImage = freezeContext.createCGImage(cropped, from: targetRect) else {
                return cropped
            }
            return CIImage(cgImage: cgImage).cropped(to: targetRect)
        }
    }
}
