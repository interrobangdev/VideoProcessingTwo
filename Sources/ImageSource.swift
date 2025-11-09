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

    /// When this image starts displaying in the composition (in seconds)
    public var compositionStartTime: Double = 0.0

    /// How long this image displays in the composition (in seconds)
    public var duration: Double = 10.0

    /// Not used for images, but required by protocol
    public var sourceStartTime: Double = 0.0

    public init(image: CGImage) {
        self.image = image
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> (any Frame)? {
        let compositionTime = cmTime.seconds

        // Check if we're within the active time window for this image
        let startTime = compositionStartTime
        let endTime = compositionStartTime + duration

        if compositionTime < startTime || compositionTime >= endTime {
            // Image is not active at this time
            return nil
        }

        return LowImageFrame(cgImage: image, time: CMTime.indefinite)
    }
}
