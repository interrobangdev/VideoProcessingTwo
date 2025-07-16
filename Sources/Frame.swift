//
//  Frame.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import CoreImage
import CoreGraphics
import AVFoundation

public protocol Frame {
    var time: CMTime { get }
    var size: CGSize { get }
    func cvPixelRepresentation() -> CVPixelBuffer?
    func ciImageRepresentation() -> CIImage?
    func platformImageRepresentation() -> PlatformImage?
}

class ImageFrame: Frame {
    let image: PlatformImage
    
    var time: CMTime {
        return CMTime.indefinite
    }
    var size: CGSize {
        return image.size
    }
    
    init(image: PlatformImage) {
        self.image = image
    }
    
    func cvPixelRepresentation() -> CVPixelBuffer? {
        return nil
    }
    
    func ciImageRepresentation() -> CIImage? {
        if let cgimg = image.cgImageRepresentation {
            return CIImage(cgImage: cgimg)
        }
        
        return nil
    }
    
    func platformImageRepresentation() -> PlatformImage? {
        return image
    }
}

class VideoFrame: Frame {
    var pixelBuffer: CVPixelBuffer
    private var internalTime: CMTime
    
    var time: CMTime {
        return internalTime
    }
    var size: CGSize {
        return pixelBuffer.size
    }
    
    init(pixelBuffer: CVPixelBuffer, time: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.internalTime = time
    }
    
    func cvPixelRepresentation() -> CVPixelBuffer? {
        return pixelBuffer
    }
    
    func ciImageRepresentation() -> CIImage? {
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
    
    func platformImageRepresentation() -> PlatformImage? {
        if let cgImage = pixelBuffer.cgImage {
            return PlatformImage(cgImage: cgImage)
        }
        
        return nil
    }
}

class LowImageFrame: Frame {
    var cgImage: CGImage
    private var internalTime: CMTime
    
    var time: CMTime {
        return internalTime
    }
    var size: CGSize {
        return cgImage.size
    }
    
    init(cgImage: CGImage, time: CMTime) {
        self.cgImage = cgImage
        self.internalTime = time
    }
    
    func cvPixelRepresentation() -> CVPixelBuffer? {
        return nil
    }
    
    func ciImageRepresentation() -> CIImage? {
        return CIImage(cgImage: cgImage)
    }
    
    func platformImageRepresentation() -> PlatformImage? {
        return PlatformImage(cgImage: cgImage)
    }
}
