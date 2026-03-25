import CoreImage
import CoreMedia

open class TwoInputBlendFilter: MultiInputFilter {
    public static let backgroundInputKey = "background"

    public var filterAnimators: [FilterAnimator]
    public var additionalInputs: [String: CIImage] = [:]

    private let filterName: String
    private let blendFilter: CIFilter?

    public init(
        filterName: String,
        backgroundImage: CIImage? = nil,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.filterName = filterName
        self.blendFilter = CIFilter(name: filterName)
        self.filterAnimators = filterAnimators
        if let backgroundImage {
            self.additionalInputs[Self.backgroundInputKey] = backgroundImage
        }
    }

    public func setBackgroundImage(_ image: CIImage?) {
        setInputImage(image, forKey: Self.backgroundInputKey)
    }

    open func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        // Most blend modes don't have scalar params. Subclasses can override.
    }

    open func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        guard let backgroundImage = additionalInputs[Self.backgroundInputKey] else {
            return image
        }

        guard let blendFilter else {
            return image.composited(over: backgroundImage)
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        if let output = blendFilter.outputImage {
            return output
        }
        return image.composited(over: backgroundImage)
    }
}

public final class AddBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CIAdditionCompositing",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}

public final class MultiplyBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CIMultiplyBlendMode",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}

public final class DivideBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CIDivideBlendMode",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}

public final class HardLightBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CIHardLightBlendMode",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}

public final class ColorDodgeBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CIColorDodgeBlendMode",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}

public final class NormalBlend: TwoInputBlendFilter {
    public init(backgroundImage: CIImage? = nil, filterAnimators: [FilterAnimator] = []) {
        super.init(
            filterName: "CISourceOverCompositing",
            backgroundImage: backgroundImage,
            filterAnimators: filterAnimators
        )
    }
}
