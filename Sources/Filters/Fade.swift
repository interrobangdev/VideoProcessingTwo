//
//  Fade.swift
//  
//
//  Created by Jake Gundersen on 5/17/24.
//

import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class Fade: Filter {
    public var filterAnimators: [FilterAnimator]
    public var fade: Double
    
    public init(fade: Double, filterAnimators: [FilterAnimator]) {
        self.filterAnimators = filterAnimators
        
        self.fade = fade
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .fade,
            let val = value as? Double {
            self.fade = val
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(fade))
        colorMatrix.inputImage = image
        
        return colorMatrix.outputImage
    }
}

