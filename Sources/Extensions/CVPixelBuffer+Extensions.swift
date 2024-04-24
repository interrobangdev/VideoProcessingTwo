//
//  CVPixelBuffer+Extensions.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import CoreMedia
import VideoToolbox

extension CVPixelBuffer {
    var width: Int {
        return CVPixelBufferGetWidth(self)
    }
    
    var height: Int {
        return CVPixelBufferGetHeight(self)
    }
    
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
    
    var cgImage: CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(self, options: nil, imageOut: &cgImage)
        return cgImage
    }
}
