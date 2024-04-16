//
//  CIImage+Extensions.swift
//  VideoProcessingSamples
//
//  Created by Jake Gundersen on 10/21/23.
//

import CoreImage

extension CIImage {
    func adjustedImage(rect: CGRect, rotation: Double) -> CIImage {
        let originalSize = self.extent.size
        
        let centerTransform = CGAffineTransform(translationX: -originalSize.width / 2.0, y: -originalSize.height / 2.0)
        var outputImage = self.transformed(by: centerTransform)
        
        let rotate = CGAffineTransform(rotationAngle: rotation)
        outputImage = outputImage.transformed(by: rotate)
        
        let xScale = rect.size.width / originalSize.width
        let yScale = rect.size.height / originalSize.height
        
        let scale = CGAffineTransform(scaleX: xScale, y: yScale)
        outputImage = outputImage.transformed(by: scale)
        
        let currentSize = originalSize * ((xScale + yScale) / 2.0)
        
        let finalTranslate = CGAffineTransform(translationX: rect.origin.x + currentSize.width / 2.0, y: rect.origin.y + currentSize.height / 2.0)
        outputImage = outputImage.transformed(by: finalTranslate)
        
        return outputImage
    }
}
