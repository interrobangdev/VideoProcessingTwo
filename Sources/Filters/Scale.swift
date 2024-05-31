//
//  Scale.swift
//
//
//  Created by Jake Gundersen on 5/16/24.
//

import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class Scale: Filter {
    public var filterAnimators: [FilterAnimator]
    
    public var scale: Double
    public var centerPoint: CGPoint
    
    public init(scale: Double, centerPoint: CGPoint, filterAnimators: [FilterAnimator]) {
        self.filterAnimators = filterAnimators
        
        self.scale = scale
        self.centerPoint = centerPoint
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .scale,
            let val = value as? Double {
            self.scale = val
        } else if filterProperty == .centerPoint,
            let pVal = value as? CGPoint {
            self.centerPoint = pVal
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        
        let translation = CGAffineTransform(translationX: -centerPoint.x, y: -centerPoint.y)
        let scaleTranslate = translation.concatenating(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let invertTranslate = scaleTranslate.concatenating(CGAffineTransform(translationX: centerPoint.x, y: centerPoint.y))
        
        return image.transformed(by: invertTranslate)
    }
}
