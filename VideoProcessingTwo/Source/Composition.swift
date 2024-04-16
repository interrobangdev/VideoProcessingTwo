//
//  Composition.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation

public protocol Transition {
    func transitionFrames(frameA: Frame, frameB: Frame, progressPercent: Double) -> Frame 
}

public struct Composition {
    let id = UUID().uuidString
    let scenes: [Scene]
    let transitions: [Transition]
    let size: CGSize
}
