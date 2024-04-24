//
//  Scene.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation

public struct Scene {
    let id = UUID().uuidString
    var duration: Double
    var frameRate: Double
    
    let group: Group
    
    public init(id: String = UUID().uuidString, duration: Double, frameRate: Double, group: Group) {
        self.duration = duration
        self.frameRate = frameRate
        self.group = group
    }
}
