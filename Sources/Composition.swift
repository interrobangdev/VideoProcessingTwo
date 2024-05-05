//
//  Composition.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation



public struct Composition {
    public enum OutputType {
        case gif
        case video
    }
    
    public let id = UUID().uuidString
    public let scenes: [Scene]
    public let renderSize: CGSize
    
    public let outputType: OutputType
    
    public init(scenes: [Scene], renderSize: CGSize, outputType: OutputType) {
        self.scenes = scenes
        self.renderSize = renderSize
        self.outputType = outputType
    }
}
