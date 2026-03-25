import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia

public class MonochromeTone: Filter {
    public var filterAnimators: [FilterAnimator]

    private let monochromeFilter = CIFilter.colorMonochrome()

    public var color: CIColor {
        get { monochromeFilter.color }
        set { monochromeFilter.color = newValue }
    }

    public var intensity: Double {
        get { Double(monochromeFilter.intensity) }
        set { monochromeFilter.intensity = Float(newValue) }
    }

    public init(
        color: CIColor = CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        intensity: Double = 1.0,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.color = color
        self.intensity = intensity
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .intensity, let value = value as? Double {
            intensity = value
        }
    }

    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        monochromeFilter.inputImage = image
        return monochromeFilter.outputImage
    }
}

public class FalseColorBlend: Filter {
    public var filterAnimators: [FilterAnimator]

    private let falseColorFilter = CIFilter.falseColor()
    private let dissolveFilter = CIFilter.dissolveTransition()

    public var firstColor: CIColor {
        get { falseColorFilter.color0 }
        set { falseColorFilter.color0 = newValue }
    }

    public var secondColor: CIColor {
        get { falseColorFilter.color1 }
        set { falseColorFilter.color1 = newValue }
    }

    /// 0 = original, 1 = full false-color.
    public var intensity: Double = 1.0

    public init(
        firstColor: CIColor = CIColor(red: 0.0, green: 0.0, blue: 0.5, alpha: 1.0),
        secondColor: CIColor = CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
        intensity: Double = 1.0,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.intensity = intensity
        self.firstColor = firstColor
        self.secondColor = secondColor
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .intensity, let value = value as? Double {
            intensity = value
        }
    }

    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        falseColorFilter.inputImage = image

        guard let falseColorImage = falseColorFilter.outputImage else {
            return image
        }

        dissolveFilter.inputImage = image
        dissolveFilter.targetImage = falseColorImage
        dissolveFilter.time = Float(intensity)
        if let output = dissolveFilter.outputImage?.cropped(to: image.extent) {
            return output
        }
        return falseColorImage.cropped(to: image.extent)
    }
}

public class HSBAdjustment: Filter {
    public var filterAnimators: [FilterAnimator]

    private let hueAdjust = CIFilter.hueAdjust()
    private let colorControls = CIFilter.colorControls()

    /// Hue angle in radians.
    public var hue: Double = 0.0
    public var saturation: Double = 1.0
    public var brightness: Double = 0.0

    public init(
        hue: Double = 0.0,
        saturation: Double = 1.0,
        brightness: Double = 0.0,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterAnimators = filterAnimators
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .hue:
            if let value = value as? Double {
                hue = value
            }
        case .saturation:
            if let value = value as? Double {
                saturation = value
            }
        case .brightness:
            if let value = value as? Double {
                brightness = value
            }
        default:
            break
        }
    }

    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        hueAdjust.inputImage = image
        hueAdjust.angle = Float(hue)

        colorControls.inputImage = hueAdjust.outputImage
        colorControls.saturation = Float(saturation)
        colorControls.brightness = Float(brightness)

        return colorControls.outputImage
    }
}
