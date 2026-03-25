import CoreGraphics
import CoreImage
import CoreMedia
import Metal

/// Stateful temporal atlas filter backed by one persistent Metal texture.
/// Frames are written one-at-a-time into a fixed grid and read back by non-negative frame offset.
public final class TemporalTextureAtlas: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    /// Non-negative frame offset relative to most recently written frame.
    /// `0` = most recent frame, `1` = previous frame, etc.
    public var frameOffset: Int {
        get { _frameOffset }
        set { _frameOffset = max(0, newValue) }
    }
    private var _frameOffset: Int

    @available(*, deprecated, message: "Use frameOffset instead.")
    public var timeOffsetFrames: Int {
        get { frameOffset }
        set { frameOffset = newValue }
    }

    /// Size of each frame cell in the atlas (defaults to 1024x1024).
    public var inputFrameSize: CGSize
    /// Hard cap for atlas width/height to control memory use.
    public var maxAtlasDimension: Int

    private let lock = NSLock()
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var atlasTexture: MTLTexture?
    private var cellTexture: MTLTexture?
    private var atlasImage: CIImage?
    private var outputTexture: MTLTexture?
    private var outputImage: CIImage?
    private var detectedMaxTextureDimension: Int?

    private var cellWidth: Int = 1024
    private var cellHeight: Int = 1024
    private var columns: Int = 1
    private var rows: Int = 1
    private var capacity: Int = 1

    private var writeIndex: Int = 0
    private var frameCount: Int = 0
    private var lastWrittenIndex: Int = 0

    public init(
        frameOffset: Int = 0,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        self._frameOffset = max(0, frameOffset)
        self.inputFrameSize = inputFrameSize
        self.maxAtlasDimension = max(1024, maxAtlasDimension)
        self.filterAnimators = filterAnimators
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
        if let device {
            self.context = CIContext(
                mtlDevice: device,
                options: [CIContextOption.cacheIntermediates: false]
            )
        } else {
            self.context = CIContext(options: [CIContextOption.cacheIntermediates: false])
        }
    }

    @available(*, deprecated, message: "Use init(frameOffset:inputFrameSize:maxAtlasDimension:filterAnimators:).")
    public convenience init(
        timeOffsetFrames: Int = 0,
        inputFrameSize: CGSize = CGSize(width: 1024, height: 1024),
        maxAtlasDimension: Int = 16384,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.init(
            frameOffset: timeOffsetFrames,
            inputFrameSize: inputFrameSize,
            maxAtlasDimension: maxAtlasDimension,
            filterAnimators: filterAnimators
        )
    }

    public func resetState() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        frameCount = 0
        lastWrittenIndex = 0
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let value = value as? Double {
                frameOffset = max(0, Int(value.rounded()))
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

        guard ensureAtlas() else {
            return image
        }

        guard
            let context,
            let atlasTexture,
            let cellTexture
        else {
            return image
        }

        let destRect = rectForIndex(writeIndex)
        let cellRect = CGRect(x: 0, y: 0, width: CGFloat(cellWidth), height: CGFloat(cellHeight))
        let writeTile = scaledImage(image, from: image.extent, to: cellRect)

        if
            let commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        {
            // Encode CI render first, then blit, to avoid "encoding in progress" assertions.
            context.render(
                writeTile,
                to: cellTexture,
                commandBuffer: commandBuffer,
                bounds: cellRect,
                colorSpace: colorSpace
            )

            
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return image
            }

            blitEncoder.copy(
                from: cellTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: cellWidth, height: cellHeight, depth: 1),
                to: atlasTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: Int(destRect.minX), y: Int(destRect.minY), z: 0)
            )
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        } else {
            context.render(
                scaledImage(image, from: image.extent, to: destRect),
                to: atlasTexture,
                commandBuffer: nil,
                bounds: destRect,
                colorSpace: colorSpace
            )
        }

        lastWrittenIndex = writeIndex
        writeIndex = (writeIndex + 1) % capacity
        frameCount = min(frameCount + 1, capacity)

        guard frameCount > 0 else {
            return image
        }

        let sampleIndex = sampledIndex(frameOffset: frameOffset)
        let sourceRect = rectForIndex(sampleIndex)

        guard let atlasImage else {
            return image
        }

        let sampledTile = atlasImage.cropped(to: sourceRect)
        if sampledTile.extent.isEmpty {
            return image
        }
        let outputExtent = CGRect(origin: .zero, size: image.extent.size)
        let sampledOutput = scaledImage(sampledTile, from: sourceRect, to: outputExtent).cropped(to: outputExtent)

        guard ensureOutputTexture(for: outputExtent.size) else {
            return sampledOutput
        }
        guard let outputTexture, let outputImage else {
            return sampledOutput
        }

        context.render(
            sampledOutput,
            to: outputTexture,
            commandBuffer: nil,
            bounds: outputExtent,
            colorSpace: colorSpace
        )

        if image.extent.origin == .zero {
            return outputImage.cropped(to: outputExtent)
        }
        return outputImage
            .cropped(to: outputExtent)
            .transformed(by: CGAffineTransform(translationX: image.extent.origin.x, y: image.extent.origin.y))
    }

    private func ensureAtlas() -> Bool {
        let requestedWidth = max(1, Int(inputFrameSize.width.rounded()))
        let requestedHeight = max(1, Int(inputFrameSize.height.rounded()))

        if atlasTexture != nil, requestedWidth == cellWidth, requestedHeight == cellHeight {
            return true
        }

        guard let device else {
            return false
        }

        let maxDim = max(1, min(detectMaxTextureDimension(device: device), maxAtlasDimension))
        let cols = max(1, maxDim / requestedWidth)
        let rws = max(1, maxDim / requestedHeight)
        let atlasWidth = cols * requestedWidth
        let atlasHeight = rws * requestedHeight

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage.renderTarget
            .union(.shaderRead)
            .union(.shaderWrite)
        descriptor.storageMode = MTLStorageMode.private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return false
        }

        let cellDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: requestedWidth,
            height: requestedHeight,
            mipmapped: false
        )
        cellDescriptor.usage = MTLTextureUsage.renderTarget
            .union(.shaderRead)
            .union(.shaderWrite)
        cellDescriptor.storageMode = MTLStorageMode.private

        guard let tmpCellTexture = device.makeTexture(descriptor: cellDescriptor) else {
            return false
        }

        cellWidth = requestedWidth
        cellHeight = requestedHeight
        columns = cols
        rows = rws
        capacity = max(1, cols * rws)

        atlasTexture = texture
        cellTexture = tmpCellTexture
        atlasImage = CIImage(
            mtlTexture: texture,
            options: [CIImageOption.colorSpace: colorSpace]
        )

        writeIndex = 0
        frameCount = 0
        lastWrittenIndex = 0
        return atlasImage != nil
    }

    private func ensureOutputTexture(for size: CGSize) -> Bool {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))

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
        descriptor.usage = MTLTextureUsage.renderTarget
            .union(.shaderRead)
            .union(.shaderWrite)
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

    private func detectMaxTextureDimension(device: MTLDevice) -> Int {
        if let detectedMaxTextureDimension {
            return detectedMaxTextureDimension
        }

        let candidates = [32768, 16384, 8192, 4096, 2048, 1024]
            .filter { $0 <= maxAtlasDimension }
        for size in candidates {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: size,
                height: size,
                mipmapped: false
            )
            descriptor.usage = MTLTextureUsage.renderTarget
                .union(.shaderRead)
                .union(.shaderWrite)
            descriptor.storageMode = MTLStorageMode.private
            if device.makeTexture(descriptor: descriptor) != nil {
                detectedMaxTextureDimension = size
                return size
            }
        }

        detectedMaxTextureDimension = 1024
        return 1024
    }

    private func sampledIndex(frameOffset requestedOffset: Int) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        let availableFrames = frameCount < capacity ? frameCount : capacity
        let clampedOffset = min(max(0, requestedOffset), max(0, availableFrames - 1))

        if frameCount < capacity {
            return (frameCount - 1) - clampedOffset
        }

        return positiveModulo(lastWrittenIndex - clampedOffset, capacity)
    }

    private func rectForIndex(_ index: Int) -> CGRect {
        let col = index % columns
        let row = index / columns
        return CGRect(
            x: CGFloat(col * cellWidth),
            y: CGFloat(row * cellHeight),
            width: CGFloat(cellWidth),
            height: CGFloat(cellHeight)
        )
    }

    private func scaledImage(_ image: CIImage, from sourceRect: CGRect, to destRect: CGRect) -> CIImage {
        let movedToOrigin = image.transformed(
            by: CGAffineTransform(
                translationX: -sourceRect.minX,
                y: -sourceRect.minY
            )
        )
        let sx = destRect.width / sourceRect.width
        let sy = destRect.height / sourceRect.height
        return movedToOrigin
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: destRect.minX, y: destRect.minY))
            .cropped(to: destRect)
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
