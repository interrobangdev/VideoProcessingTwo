import CoreImage
import Metal

class GlitchFilter: CIFilter {
    private var kernel: CIColorKernel?
    
    var inputImage: CIImage?
    var intensity: Float = 1.0

    override init() {
        super.init()
        
        let url = Bundle.module.url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        
        kernel = try? CIColorKernel(functionName: "glitchEffect",
                                    fromMetalLibraryData: data)
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
        guard let inputImage = inputImage, let kernel = kernel else { return nil }
        return kernel.apply(extent: inputImage.extent,
                          arguments: [inputImage, intensity])
    }
}
