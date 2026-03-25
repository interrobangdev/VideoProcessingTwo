import CoreImage
import CoreMedia
import Foundation

/// Mirrors the image across a line defined by a point and angle.
/// The preserved side is chosen using the image center relative to that line.
public final class Mirror: Filter {
    public var filterAnimators: [FilterAnimator]

    /// A point on the mirror axis, in image coordinates.
    public var point: CGPoint {
        didSet {
            mirrorKernelFilter.point = point
        }
    }

    /// Mirror-axis angle in radians.
    public var angle: Double {
        didSet {
            mirrorKernelFilter.angle = Float(angle)
        }
    }

    private let mirrorKernelFilter = MirrorKernelFilter()

    public init(
        point: CGPoint = CGPoint(x: 960, y: 540),
        angle: Double = 0.0,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.point = point
        self.angle = angle

        mirrorKernelFilter.point = point
        mirrorKernelFilter.angle = Float(angle)
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .centerPoint:
            if let value = value as? CGPoint {
                point = value
            }
        case .angle, .rotation:
            if let value = value as? Double {
                angle = value
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
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        let centerDistance = ((center.x - point.x) * normal.x) + ((center.y - point.y) * normal.y)
        let keepSign: Float = centerDistance < 0 ? -1.0 : 1.0

        mirrorKernelFilter.inputImage = image.clampedToExtent()
        mirrorKernelFilter.outputExtent = extent
        mirrorKernelFilter.keepSign = keepSign

        if let output = mirrorKernelFilter.outputImage {
            return output.cropped(to: extent)
        }

        return image
    }
}

private final class MirrorKernelFilter: CIFilter {
    private static var cachedKernel: CIKernel?

    private var kernel: CIKernel? {
        if Self.cachedKernel == nil {
            Self.cachedKernel = Self.createKernel()
        }
        return Self.cachedKernel
    }

    var inputImage: CIImage?
    var point: CGPoint = .zero
    var angle: Float = 0.0
    var keepSign: Float = 1.0
    var outputExtent: CGRect = .zero

    private static func createKernel() -> CIKernel? {
        do {
            guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try CIKernel(functionName: "mirrorEffect", fromMetalLibraryData: data)
        } catch {
            return nil
        }
    }

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var outputImage: CIImage? {
        guard let inputImage, let kernel, outputExtent.width > 0, outputExtent.height > 0 else {
            return nil
        }

        return kernel.apply(
            extent: outputExtent,
            roiCallback: { _, _ in inputImage.extent },
            arguments: [
                inputImage,
                CIVector(x: point.x, y: point.y),
                NSNumber(value: angle),
                NSNumber(value: keepSign)
            ]
        )
    }
}
