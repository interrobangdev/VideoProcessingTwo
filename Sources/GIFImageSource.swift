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

    /// When this GIF starts playing in the composition (in seconds)
    public var compositionStartTime: Double = 0.0

    /// How long this GIF plays in the composition (in seconds)
    public var duration: Double = 10.0

    /// What time in the source GIF to start from (in seconds)
    public var sourceStartTime: Double = 0.0

    public init(image: GIFImage, loop: Bool = true) {
        self.image = image
        self.loop = loop
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> (any Frame)? {
        let compositionTime = cmTime.seconds

        // Check if we're within the active time window for this GIF
        let startTime = compositionStartTime
        let endTime = compositionStartTime + duration

        if compositionTime < startTime || compositionTime >= endTime {
            // GIF is not active at this time
            return nil
        }

        // Calculate time within the GIF's playback window
        let timeIntoGIF = compositionTime - startTime + sourceStartTime

        var time = timeIntoGIF
        let gifDuration = Double(image.gifDuration)

        // Loop the GIF based on its duration
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

