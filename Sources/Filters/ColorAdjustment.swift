import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class ColorAdjustment: Filter {
    public var filterAnimators: [FilterAnimator]
    
    private let colorControls = CIFilter.colorControls()

    public var brightness: Double {
        set(value) {
            colorControls.brightness = Float(value)
        }
        get {
            return Double(colorControls.brightness)
        }
    }

    public var contrast: Double {
        set(value) {
            colorControls.contrast = Float(value)
        }
        get {
            return Double(colorControls.contrast)
        }
    }

    public var saturation: Double {
        set(value) {
            colorControls.saturation = Float(value)
        }
        get {
            return Double(colorControls.saturation)
        }
    }
    
    public init(brightness: Double = 0.0, contrast: Double = 1.0, saturation: Double = 1.0, filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .brightness:
            if let val = value as? Double {
                self.brightness = val
            }
        case .contrast:
            if let val = value as? Double {
                self.contrast = val
            }
        case .saturation:
            if let val = value as? Double {
                self.saturation = val
            }
        default:
            break
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        colorControls.inputImage = image
        return colorControls.outputImage
    }
}
