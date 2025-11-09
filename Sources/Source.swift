//
//  Source.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation
import CoreMedia

public protocol Source {
    /// When this source starts playing in the composition (in seconds)
    var compositionStartTime: Double { get set }

    /// How long this source plays in the composition (in seconds)
    var duration: Double { get set }

    /// What time in the source media to start from (in seconds)
    var sourceStartTime: Double { get set }

    func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> Frame?
}
