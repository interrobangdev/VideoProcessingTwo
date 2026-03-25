import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

public class NormalAmountBlend: MultiInputFilter {
    public static let blendInputKey = "blend"

    public var filterAnimators: [FilterAnimator]
    public var additionalInputs: [String: CIImage] = [:]
    private let blendAlphaMatrix: CIFilter = CIFilter.colorMatrix()
    private let inputAlphaMatrix: CIFilter = CIFilter.colorMatrix()

    public var image1Amount: Double = 1.0
    public var image2Amount: Double = 1.0

    public init(
        image1Amount: Double = 1.0,
        image2Amount: Double = 1.0,
        blendImage: CIImage? = nil,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.image1Amount = image1Amount
        self.image2Amount = image2Amount
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
        case .image1Amount:
            if let value = value as? Double {
                image1Amount = value
            }
        case .image2Amount:
            if let value = value as? Double {
                image2Amount = value
            }
        default:
            break
        }
    }

    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        guard let blendImage = additionalInputs[Self.blendInputKey] else {
            return image
        }

        // Approximation of GPUImageNormalAmountBlend using Core Image:
        // scale each input alpha independently, then SourceOver composite.
        let scaledBlend = alphaScaledImage(blendImage, amount: image1Amount, filter: blendAlphaMatrix)
        let scaledInput = alphaScaledImage(image, amount: image2Amount, filter: inputAlphaMatrix)
        return scaledBlend.composited(over: scaledInput).cropped(to: image.extent)
    }

    private func alphaScaledImage(_ image: CIImage, amount: Double, filter: CIFilter) -> CIImage {
        let clampedAmount = max(0.0, amount)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(clampedAmount)), forKey: "inputAVector")
        if let output = filter.outputImage {
            return output
        }
        return image
    }
}
