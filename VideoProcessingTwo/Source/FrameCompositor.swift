//
//  FrameCompositor.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/6/24.
//

import Foundation
import CoreImage
import CoreMedia

public typealias FrameCallback = (CIImage, Double) -> ()
public typealias CompletionCallback = (Bool) -> ()

public class FrameCompositor {
    public init() {}
    
    public func generateFrames(scene: Scene, compositionTimeOffset: Double, realTime: Bool, frameCallback: FrameCallback, completion: CompletionCallback) {
        let frameCount = Int(scene.duration * scene.frameRate)
        
//        var startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<frameCount {
            let frameTime = Double(i) * (1.0 / scene.frameRate)
            
            if let outputImage = scene.group.renderGroup(frameTime: frameTime, compositionTimeOffset: compositionTimeOffset) {
                
                frameCallback(outputImage, frameTime)
            }
        }
        
        completion(true)
    }
}
