import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

/// CI-only bloom/glow wrapper for stylized highlight lift.
public class BloomGlow: Filter {
    public var filterAnimators: [FilterAnimator]

    private let bloom = CIFilter.bloom()

    public var radius: Double {
        get { Double(bloom.radius) }
        set { bloom.radius = Float(newValue) }
    }

    public var intensity: Double {
        get { Double(bloom.intensity) }
        set { bloom.intensity = Float(newValue) }
    }

    public init(radius: Double = 12.0, intensity: Double = 0.5, filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators
        self.radius = radius
        self.intensity = intensity
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
        bloom.inputImage = image
        return bloom.outputImage?.cropped(to: image.extent)
    }
}
