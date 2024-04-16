//
//  Group.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/9/24.
//

import Foundation
import CoreImage
import CoreMedia

public protocol Mask {
    func maskImage(image: CIImage) -> CIImage?
}

public struct Group {
    var id: String = UUID().uuidString
    var groups: [Group]
    var layers: [Layer]
    var filters: [Filter]
    var mask: Mask?
    
    public init(id: String = UUID().uuidString, groups: [Group], layers: [Layer], filters: [Filter], mask: Mask?) {
        self.id = id
        self.groups = groups
        self.layers = layers
        self.filters = filters
        self.mask = mask
    }
    
    func renderGroup(frameTime: Double, compositionTimeOffset: Double) -> CIImage? {
        var outputImage: CIImage?

        if groups.count > 0 {
            for group in groups {
                if let outImage = group.renderGroup(frameTime: frameTime, compositionTimeOffset: compositionTimeOffset) {
                    if let oi = outputImage {
                        outputImage = outImage.composited(over: oi)
                    } else {
                        outputImage = outImage
                    }
                }
            }
        }
        
        if layers.count > 0 {
            for layer in layers {
                if let outImage = layer.renderLayer(frameTime: frameTime) {
                    if let oi = outputImage {
                        outputImage = outImage.composited(over: oi)
                    } else {
                        outputImage = outImage
                    }
                }
            }
        }
        
        for filter in filters {
            if let oi = outputImage {
                outputImage = filter.filterContent(image: oi, sourceTime: nil, sceneTime: frameTime.cmTime(), compositionTime: (frameTime + compositionTimeOffset).cmTime())
            }
        }
        
        return outputImage
    }
}
