//
//  GaussianBlur.swift
//
//
//  Created by Jake Gundersen on 5/5/24.
//

import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class GaussianBlur: Filter {
    let blur = CIFilter.gaussianBlur()
    public var filterConfig: FilterConfig
    public var radius: Float
    
    public init(radius: Float, filterConfig: FilterConfig) {
        self.radius = radius
        self.filterConfig = filterConfig
    }
    
    public func configureFilter() {
        for option in filterConfig.configOptions {
            if option.configType == .coreImage {
                if let rad = option.configValue() as? Float {
                    blur.radius = rad
                }
            }
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        
        configureFilter()
        blur.inputImage = image
        
        return blur.outputImage
    }
}
