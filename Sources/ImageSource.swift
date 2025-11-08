//
//  ImageSource.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation
import CoreGraphics
import CoreMedia

public class ImageSource: Source {
    let image: CGImage
    
    public init(image: CGImage) {
        self.image = image
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> (any Frame)? {
        return LowImageFrame(cgImage: image, time: CMTime.indefinite)
    }
}
