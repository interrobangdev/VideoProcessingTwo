//
//  Double+Extensions.swift
//  VideoProcessingSamples
//
//  Created by Jake Gundersen on 10/16/23.
//

import Foundation
import CoreMedia

extension Double {
    func cmTime(preferredTimeScale: CMTimeScale = 600) -> CMTime {
        return CMTime(seconds: self, preferredTimescale: preferredTimeScale)
    }
}
