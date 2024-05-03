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
    
    let id = UUID().uuidString
    let scenes: [Scene]
    let renderSize: CGSize
    
    let outputType: OutputType
}
