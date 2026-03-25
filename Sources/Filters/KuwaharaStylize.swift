import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation

/// Kuwahara stylization powered by a custom Metal Core Image kernel.
/// Falls back to CIKuwahara when Metal kernel resources are unavailable.
public class KuwaharaStylize: Filter {
    public var filterAnimators: [FilterAnimator]

    /// 0...1 blend between original and stylized output.
    public var intensity: Double {
        didSet {
            kuwaharaKernelFilter.intensity = Float(clamped(intensity, min: 0.0, max: 1.0))
        }
    }

    /// Neighborhood radius in pixels.
    public var radius: Double {
        didSet {
            kuwaharaKernelFilter.radius = Float(max(1.0, radius))
        }
    }

    private let kuwaharaKernelFilter = KuwaharaKernelFilter()
    private let fallbackKuwahara = CIFilter(name: "CIKuwahara")
    private let dissolveFilter = CIFilter.dissolveTransition()

    public init(radius: Double = 8.0, intensity: Double = 1.0, filterAnimators: [FilterAnimator] = []) {
        self.radius = radius
        self.intensity = intensity
        self.filterAnimators = filterAnimators
        kuwaharaKernelFilter.radius = Float(max(1.0, radius))
        kuwaharaKernelFilter.intensity = Float(clamped(intensity, min: 0.0, max: 1.0))
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .radius:
            if let value = value as? Double {
                radius = value
            }
        case .intensity:
            if let value = value as? Double {
                intensity = value
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
        kuwaharaKernelFilter.inputImage = image
        if let stylized = kuwaharaKernelFilter.outputImage?.cropped(to: image.extent) {
            return stylized
        }

        guard let fallbackKuwahara else {
            return image
        }

        fallbackKuwahara.setValue(image, forKey: kCIInputImageKey)
        fallbackKuwahara.setValue(max(1.0, radius), forKey: kCIInputRadiusKey)
        guard let fallbackStylized = fallbackKuwahara.outputImage?.cropped(to: image.extent) else {
            return image
        }

        dissolveFilter.inputImage = image
        dissolveFilter.targetImage = fallbackStylized
        dissolveFilter.time = Float(clamped(intensity, min: 0.0, max: 1.0))
        if let output = dissolveFilter.outputImage?.cropped(to: image.extent) {
            return output
        }
        return fallbackStylized
    }

    private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

private final class KuwaharaKernelFilter: CIFilter {
    private static var cachedKernel: CIKernel?

    private var kernel: CIKernel? {
        if Self.cachedKernel == nil {
            Self.cachedKernel = Self.createKernel()
        }
        return Self.cachedKernel
    }

    var inputImage: CIImage?
    var radius: Float = 8.0
    var intensity: Float = 1.0

    private static func createKernel() -> CIKernel? {
        do {
            guard
                let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
                let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            return try CIKernel(functionName: "kuwaharaEffect", fromMetalLibraryData: data)
        } catch {
            return nil
        }
    }

    override init() {
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var outputImage: CIImage? {
        guard let inputImage, let kernel else { return nil }

        let safeRadius = max(1.0, radius)
        let blend = max(0.0, min(1.0, intensity))
        let radiusPadding = CGFloat(safeRadius)

        return kernel.apply(
            extent: inputImage.extent,
            roiCallback: { _, rect in
                rect.insetBy(dx: -radiusPadding, dy: -radiusPadding)
            },
            arguments: [
                inputImage,
                NSNumber(value: safeRadius),
                NSNumber(value: blend),
            ]
        )
    }
}
