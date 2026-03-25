import CoreMedia
import CoreImage

@available(iOS 15.0, *)
public class GlitchEffect: Filter {
    public var filterAnimators: [FilterAnimator]
    
    private let colorControls = CIFilter.colorControls()
    private let pixellate = CIFilter.pixellate()
    private let glitchFilter = GlitchFilter()

    public var intensity: Double = 1.0 {
        didSet {
            updateFilters()
        }
    }

    public init(intensity: Double = 1.0, filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators
        self.intensity = intensity
        updateFilters()
    }
    
    private func updateFilters() {
        colorControls.saturation = Float(1.2 + intensity * 0.9)
        colorControls.contrast = Float(1.0 + intensity * 0.45)
        pixellate.scale = Float(2.0 + intensity * 12.0)
        glitchFilter.intensity = Float(intensity)
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let val = value as? Double {
                self.intensity = val
            }
        default:
            break
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        let resolvedTime = compositionTime ?? sceneTime ?? sourceTime ?? .zero
        let seconds = CMTimeGetSeconds(resolvedTime)
        glitchFilter.time = Float(seconds.isFinite ? seconds : 0.0)
        colorControls.inputImage = image
        pixellate.inputImage = colorControls.outputImage
        glitchFilter.inputImage = pixellate.outputImage
        return glitchFilter.outputImage
    }
}
