//
//  Source.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation
import CoreMedia

public protocol Source {
    func getFrameAtTime(cmTime: CMTime) -> Frame?
}
