import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

/// Wrapper around CIComicEffect with blendable intensity.
public class ComicStylize: Filter {
    public var filterAnimators: [FilterAnimator]

    /// 0...1 blend between original and comic output.
    public var intensity: Double

    private let comicFilter = CIFilter.comicEffect()
    private let dissolveFilter = CIFilter.dissolveTransition()

    public init(intensity: Double = 1.0, filterAnimators: [FilterAnimator] = []) {
        self.intensity = intensity
        self.filterAnimators = filterAnimators
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
        comicFilter.inputImage = image
        guard let comicImage = comicFilter.outputImage else {
            return image
        }

        dissolveFilter.inputImage = image
        dissolveFilter.targetImage = comicImage
        dissolveFilter.time = Float(max(0.0, min(1.0, intensity)))
        if let output = dissolveFilter.outputImage?.cropped(to: image.extent) {
            return output
        }
        return comicImage.cropped(to: image.extent)
    }
}
