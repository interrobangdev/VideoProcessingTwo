//
//  Translate.swift
//
//
//  Created by Jake Gundersen on 5/17/24.
//

import CoreMedia
import CoreImage
import CoreImage.CIFilterBuiltins

public class Translate: Filter {
    public var filterAnimators: [FilterAnimator]
    
    public var translation: CGPoint
    
    public init(translation: CGPoint, filterAnimators: [FilterAnimator]) {
        self.filterAnimators = filterAnimators
        
        self.translation = translation
    }
    
    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        if filterProperty == .translation,
            let val = value as? CGPoint {
            self.translation = val
        }
    }
    
    public func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        let inputExtent = image.extent
        
        let translateTransform = CGAffineTransform(translationX: translation.x, y: translation.y)
        
        return image.transformed(by: translateTransform)
    }
}

