import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

public class SepiaTone: Filter {
    public var filterAnimators: [FilterAnimator]

    private let sepiaFilter = CIFilter.sepiaTone()

    public var intensity: Double {
        get { Double(sepiaFilter.intensity) }
        set { sepiaFilter.intensity = Float(newValue) }
    }

    public init(intensity: Double = 1.0, filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators
        self.intensity = intensity
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .intensity, let value = value as? Double {
            intensity = value
        }
    }

    public func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        sepiaFilter.inputImage = image
        return sepiaFilter.outputImage
    }
}
