import CoreImage
import Metal
import Foundation

class GlitchFilter: CIFilter {
    private static var cachedKernel: CIKernel?

    private var kernel: CIKernel? {
        if Self.cachedKernel == nil {
            Self.cachedKernel = Self.createKernel()
        }
        return Self.cachedKernel
    }

    var inputImage: CIImage?
    var intensity: Float = 1.0

    private static func createKernel() -> CIKernel? {
        do {
            // Load the compiled default.metallib from the bundle
            guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib") else {
                return nil
            }

            guard let data = try? Data(contentsOf: url) else {
                return nil
            }

            // Create CIKernel from the compiled Metal library
            return try CIKernel(functionName: "glitchEffect", fromMetalLibraryData: data)

        } catch {
            return nil
        }
    }

    override init() {
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var inputKeys: [String] {
        return ["inputImage", "intensity"]
    }

    override var outputKeys: [String] {
        return ["outputImage"]
    }

    override var attributes: [String : Any] {
        return [
            kCIAttributeFilterDisplayName: "Glitch Filter",
            
            "inputImage": [kCIAttributeIdentity: 0,
                           kCIAttributeClass: "CIImage",
                           kCIAttributeDisplayName: "Image",
                           kCIAttributeType: kCIAttributeTypeImage],
            
            "intensity": [kCIAttributeIdentity: 0,
                          kCIAttributeClass: "NSNumber",
                          kCIAttributeDefault: 1.0,
                          kCIAttributeDisplayName: "Intensity",
                          kCIAttributeMin: 0.0,
                          kCIAttributeMax: 10.0,
                          kCIAttributeSliderMin: 0.0,
                          kCIAttributeSliderMax: 10.0,
                          kCIAttributeType: kCIAttributeTypeScalar]
        ]
    }

    override var outputImage: CIImage? {
        guard let inputImage = inputImage, let kernel = kernel else {
            return inputImage
        }

        return kernel.apply(extent: inputImage.extent,
                           roiCallback: { _, rect in return rect },
                           arguments: [inputImage, NSNumber(value: intensity)])
    }
}
