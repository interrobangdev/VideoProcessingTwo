//
//  CGImage+Extensions.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import CoreGraphics

extension CGImage {
    var size: CGSize {
        return CGSize(width: self.width, height: self.height)
    }
    
    func pixelData() -> [UInt8]? {
        let size = CGSize(width: self.width, height: self.height)
        let dataSize = size.width * size.height * 4
        var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(size.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        return pixelData
    }
}
