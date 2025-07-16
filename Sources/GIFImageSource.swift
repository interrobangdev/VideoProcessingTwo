//
//  GIFImageSource.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/6/24.
//

//import UIKit
import CoreGraphics
import CoreMedia

public class GIFImageSource: Source {
    let image: GIFImage
    var loop: Bool
    
    public init(image: GIFImage, loop: Bool = true) {
        self.image = image
        self.loop = loop
    }
    
    public func getFrameAtTime(cmTime: CMTime) -> (any Frame)? {
        var time = cmTime.seconds
        let gifDuration = Double(image.gifDuration)
        if loop,
           time > gifDuration {
            time = time.truncatingRemainder(dividingBy: gifDuration)
        }
        if let cgImage = image.getImageAtTime(time: time.cmTime()) {
            return LowImageFrame(cgImage: cgImage, time: cmTime)
        }
        
        return nil
    }
}

