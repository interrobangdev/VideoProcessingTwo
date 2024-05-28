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
    public var filterAnimators: [FilterAnimator]
    
    let blur = CIFilter.gaussianBlur()

    public var radius: Double {
        set(value) {
            blur.radius = Float(value)
        }
        get {
            return Double(blur.radius)
        }
    }
    
    public init(radius: Double, filterAnimators: [FilterAnimator]) {
        self.filterAnimators = filterAnimators
        self.radius = radius
    }
    
    /*
    public func configureFilter() {
        for option in filterConfig.configOptions {
            if option.configType == .coreImage {
                if let rad = option.configValue() as? Float {
                    blur.radius = rad
                }
            }
        }
    }*/
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .radius,
            let val = value as? Double {
            self.radius = val
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        
        blur.inputImage = image
        
        return blur.outputImage
    }
}
