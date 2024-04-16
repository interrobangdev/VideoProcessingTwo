//
//  GIFWriter.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/6/24.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public class GIFWriter {
    var destination: CGImageDestination
    var properties = [String: Any]()
    
    public init?(url: URL, frameCount: Int) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            return nil
        }
        destination = dest
        
        let gifProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
    }
    
    public func addFrame(image: CGImage, delay: Double) {
        let frameProperties: [String: Any] = [kCGImagePropertyGIFDelayTime as String: delay]
        
        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
    }
    
    public func finalize() {
        CGImageDestinationFinalize(destination)
    }
}
