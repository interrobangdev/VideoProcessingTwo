import CoreImage
import CoreMedia
import Foundation

public class Voronoi: Filter {
    public var filterAnimators: [FilterAnimator]

    /// Cell size in pixels.
    public var scale: Double {
        didSet {
            voronoiFilter.cellSize = Float(max(1.0, scale))
        }
    }

    /// Seed jitter amount in 0...1.
    public var radius: Double {
        didSet {
            voronoiFilter.jitter = Float(clamped(radius, min: 0.0, max: 1.0))
        }
    }

    /// Blend between source image and Voronoi stylization in 0...1.
    public var intensity: Double {
        didSet {
            voronoiFilter.intensity = Float(clamped(intensity, min: 0.0, max: 1.0))
        }
    }

    /// Boundary thickness in normalized cell-space.
    public var edgeWidth: Double {
        didSet {
            voronoiFilter.edgeWidth = Float(max(0.001, edgeWidth))
        }
    }

    /// Boundary darkening amount in 0...1.
    public var edgeIntensity: Double {
        didSet {
            voronoiFilter.edgeIntensity = Float(clamped(edgeIntensity, min: 0.0, max: 1.0))
        }
    }

    /// Per-cell color variation amount in 0...1.
    public var colorVariation: Double {
        didSet {
            voronoiFilter.colorVariation = Float(clamped(colorVariation, min: 0.0, max: 1.0))
        }
    }

    /// Animated drift speed for cell seeds.
    public var driftSpeed: Double {
        didSet {
            voronoiFilter.driftSpeed = Float(max(0.0, driftSpeed))
        }
    }

    private let voronoiFilter = VoronoiKernelFilter()
    private let fallbackCrystallize = CIFilter.crystallize()
    private let dissolveFilter = CIFilter.dissolveTransition()

    public init(
        scale: Double = 32.0,
        radius: Double = 0.9,
        intensity: Double = 1.0,
        edgeWidth: Double = 0.09,
        edgeIntensity: Double = 0.75,
        colorVariation: Double = 0.35,
        driftSpeed: Double = 0.25,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.scale = scale
        self.radius = radius
        self.intensity = intensity
        self.edgeWidth = edgeWidth
        self.edgeIntensity = edgeIntensity
        self.colorVariation = colorVariation
        self.driftSpeed = driftSpeed

        voronoiFilter.cellSize = Float(max(1.0, scale))
        voronoiFilter.jitter = Float(clamped(radius, min: 0.0, max: 1.0))
        voronoiFilter.intensity = Float(clamped(intensity, min: 0.0, max: 1.0))
        voronoiFilter.edgeWidth = Float(max(0.001, edgeWidth))
        voronoiFilter.edgeIntensity = Float(clamped(edgeIntensity, min: 0.0, max: 1.0))
        voronoiFilter.colorVariation = Float(clamped(colorVariation, min: 0.0, max: 1.0))
        voronoiFilter.driftSpeed = Float(max(0.0, driftSpeed))
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .scale:
            if let value = value as? Double {
                scale = value
            }
        case .radius:
            if let value = value as? Double {
                radius = value
            }
        case .intensity:
            if let value = value as? Double {
                intensity = value
            }
        case .filterStrength:
            if let value = value as? Double {
                edgeIntensity = value
            }
        case .hue:
            if let value = value as? Double {
                colorVariation = value
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
        let time = CMTimeGetSeconds(compositionTime ?? sceneTime ?? sourceTime ?? .zero)
        voronoiFilter.time = Float(time.isFinite ? time : 0.0)
        voronoiFilter.inputImage = image
        if let output = voronoiFilter.outputImage {
            return output.cropped(to: image.extent)
        }

        fallbackCrystallize.inputImage = image
        fallbackCrystallize.radius = Float(max(1.0, scale))
        guard let fallbackOutput = fallbackCrystallize.outputImage?.cropped(to: image.extent) else {
            return image
        }

        dissolveFilter.inputImage = image
        dissolveFilter.targetImage = fallbackOutput
        dissolveFilter.time = Float(clamped(intensity, min: 0.0, max: 1.0))
        if let blended = dissolveFilter.outputImage?.cropped(to: image.extent) {
            return blended
        }
        return fallbackOutput
    }

    private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

private final class VoronoiKernelFilter: CIFilter {
    private static var cachedKernel: CIKernel?

    private var kernel: CIKernel? {
        if Self.cachedKernel == nil {
            Self.cachedKernel = Self.createKernel()
        }
        return Self.cachedKernel
    }

    var inputImage: CIImage?
    var cellSize: Float = 32.0
    var jitter: Float = 0.9
    var intensity: Float = 1.0
    var edgeWidth: Float = 0.09
    var edgeIntensity: Float = 0.75
    var colorVariation: Float = 0.35
    var driftSpeed: Float = 0.25
    var time: Float = 0.0

    private static func createKernel() -> CIKernel? {
        do {
            guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try CIKernel(functionName: "voronoiEffect", fromMetalLibraryData: data)
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
        guard let inputImage, let kernel else {
            return nil
        }

        if let output = kernel.apply(
            extent: inputImage.extent,
            roiCallback: { _, rect in rect },
            arguments: [
                inputImage,
                NSNumber(value: cellSize),
                NSNumber(value: jitter),
                NSNumber(value: intensity),
                NSNumber(value: edgeWidth),
                NSNumber(value: edgeIntensity),
                NSNumber(value: colorVariation),
                NSNumber(value: driftSpeed),
                NSNumber(value: time),
            ]
        ) {
            return output
        }

        return nil
    }
}
