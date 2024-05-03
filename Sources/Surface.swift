//
//  Surface.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation

public class Surface {
    let id = UUID().uuidString
    let source: Source
    let frame: CGRect
    let rotation: Double
    
    public init(id: String = UUID().uuidString, source: Source, frame: CGRect, rotation: Double) {
        self.source = source
        self.frame = frame
        self.rotation = rotation
    }
}
