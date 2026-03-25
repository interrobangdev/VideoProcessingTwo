import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

public class DissolveBlend: MultiInputFilter {
    public static let blendInputKey = "blend"

    public var filterAnimators: [FilterAnimator]
    public var additionalInputs: [String: CIImage] = [:]
    private let dissolveFilter = CIFilter.dissolveTransition()

    public var mix: Double = 0.5

    public init(mix: Double = 0.5, blendImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        self.mix = mix
        self.filterAnimators = filterAnimators
        if let blendImage {
            self.additionalInputs[Self.blendInputKey] = blendImage
        }
    }

    public func setBlendImage(_ image: CIImage?) {
        setInputImage(image, forKey: Self.blendInputKey)
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .mix:
            if let value = value as? Double {
                mix = value
            }
        case .intensity:
            if let value = value as? Double {
                mix = value
            }
        default:
            break
        }
    }

    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        guard let blendImage = additionalInputs[Self.blendInputKey] else {
            return image
        }

        dissolveFilter.inputImage = image
        dissolveFilter.targetImage = blendImage
        dissolveFilter.time = Float(mix)
        if let output = dissolveFilter.outputImage?.cropped(to: image.extent) {
            return output
        }
        return image
    }
}
