//
//  Rotate.swift
//  
//
//  Created by Jake Gundersen on 5/17/24.
//

import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class Rotate: Filter {
    public var filterAnimators: [FilterAnimator]
    
    public var rotation: Double
    public var centerPoint: CGPoint
    
    public init(rotation: Double, centerPoint: CGPoint, filterAnimators: [FilterAnimator]) {
        self.filterAnimators = filterAnimators
        
        self.rotation = rotation
        self.centerPoint = centerPoint
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .rotation,
            let val = value as? Double {
            self.rotation = val
        } else if filterProperty == .centerPoint,
            let pVal = value as? CGPoint {
            self.centerPoint = pVal
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        let inputExtent = image.extent
        
        let translation = CGAffineTransform(translationX: -centerPoint.x, y: -centerPoint.y)
        let rotateTranslate = translation.concatenating(CGAffineTransform(rotationAngle: CGFloat(rotation)))
        let invertTranslate = rotateTranslate.concatenating(CGAffineTransform(translationX: centerPoint.x, y: centerPoint.y))
        
        return image.transformed(by: invertTranslate)
    }
}

