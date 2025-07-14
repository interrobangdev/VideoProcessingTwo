import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class Crystallize: Filter {
    public var filterAnimators: [FilterAnimator]
    
    private let crystallizeFilter = CIFilter.crystallize()

    public var radius: Double {
        set(value) {
            crystallizeFilter.radius = Float(value)
        }
        get {
            return Double(crystallizeFilter.radius)
        }
    }

    public var center: CGPoint {
        set(value) {
            crystallizeFilter.center = value
        }
        get {
            return crystallizeFilter.center
        }
    }
    
    public init(radius: Double = 20.0, center: CGPoint = CGPoint(x: 150, y: 150), filterAnimators: [FilterAnimator] = []) {
        self.filterAnimators = filterAnimators
        self.radius = radius
        self.center = center
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .radius:
            if let val = value as? Double {
                self.radius = val
            }
        case .centerPoint:
            if let val = value as? CGPoint {
                self.center = val
            }
        default:
            break
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        crystallizeFilter.inputImage = image
        return crystallizeFilter.outputImage
    }
}
