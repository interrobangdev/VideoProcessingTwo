//
//  GIFImage.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/6/24.
//

import UIKit
import CoreMedia

enum GifParseError: Error {
    case invalidFilename
    case noImages
    case noProperties
    case noGifDictionary
    case noTimingInfo
}

extension GifParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidFilename:
            return "Invalid file name"
        case .noImages, .noProperties, .noGifDictionary, .noTimingInfo:
            return "Invalid gif file"
        }
    }
}

public class GIFImage {
    var size: CGSize = .zero
    var imageSource: CGImageSource?
    var gifDelays: [Float] = []
    var gifDuration: Float = 0.0
    
    public init?(gifData: Data) {
        guard let imgSource = CGImageSourceCreateWithData(gifData as CFData, nil) else { return nil }
        
        if let delays = try? getGifDelays(imgSource) {
            self.gifDelays = delays
            self.gifDuration = delays.reduce(0, +)
        } else {
            return nil
        }
        
        guard let oneFrame = CGImageSourceCreateImageAtIndex(imgSource, 0, nil) else { return nil }
        
        self.size = CGSize(width: oneFrame.width, height: oneFrame.height)
        self.imageSource = imgSource
    }
    
    func getImageAtTime(time: CMTime) -> CGImage? {
        var currentTime = 0.0
        var index = -1
        
        for i in 0..<gifDelays.count {
            let gifTime = gifDelays[i]
            
            if time.seconds >= currentTime &&
                time.seconds < currentTime + Double(gifTime) {
                index = i
                break
            }
            
            currentTime += Double(gifTime)
        }
        
        if let source = imageSource,
            index != -1 {
            return CGImageSourceCreateImageAtIndex(source, index, nil)
        }
        
        return nil
    }
    
    private func getGifDelays(_ imageSource:CGImageSource) throws -> [Float] {
        let imageCount = CGImageSourceGetCount(imageSource)
        
        guard imageCount > 0 else {
            throw GifParseError.noImages
        }
        
        var imageProperties = [CFDictionary]()
        
        for i in 0..<imageCount {
            if let dict = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) {
                imageProperties.append(dict)
            } else {
                throw GifParseError.noProperties
            }
        }
        
        let frameProperties = try imageProperties.map() { (dict: CFDictionary) -> CFDictionary in
            let key = Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()
            let value = CFDictionaryGetValue(dict, key)
            
            if value == nil {
                throw GifParseError.noGifDictionary
            }
            
            return unsafeBitCast(value, to: CFDictionary.self)
        }
        
        let EPS:Float = 1e-6
        
        let frameDelays:[Float] = try frameProperties.map() {
            let unclampedKey = Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()
            let unclampedPointer:UnsafeRawPointer? = CFDictionaryGetValue($0, unclampedKey)
            
            if let value = convertToDelay(unclampedPointer), value >= EPS {
                return value
            }
            
            let clampedKey = Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()
            let clampedPointer:UnsafeRawPointer? = CFDictionaryGetValue($0, clampedKey)
            
            if let value = convertToDelay(clampedPointer) {
                return value
            }
            
            throw GifParseError.noTimingInfo
        }
        
        return frameDelays
    }
    
    private func convertToDelay(_ pointer:UnsafeRawPointer?) -> Float? {
        if pointer == nil {
            return nil
        }
        
        return unsafeBitCast(pointer, to:AnyObject.self).floatValue
    }
}

