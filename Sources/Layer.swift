//
//  LayerModel.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation
import CoreImage
import CoreMedia
import AVFoundation

public class Layer {
    let id = UUID().uuidString
    public var surfaces: [Surface]
    
    public init(id: String = UUID().uuidString, surfaces: [Surface]) {
        self.surfaces = surfaces
    }
    
    func renderLayer(frameTime: Double, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]? = nil) -> CIImage? {
        var outputImage: CIImage?
        for surface in surfaces {
            let frame = surface.source.getFrameAtTime(cmTime: frameTime.cmTime(), framesByTrackID: framesByTrackID)
            let frameCIImage = frame?.ciImageRepresentation()

            if let adjusted = frameCIImage?.adjustedImage(rect: surface.frame, rotation: surface.rotation) {

                if let oi = outputImage {
                    outputImage = adjusted.composited(over: oi)
                } else {
                    outputImage = adjusted
                }
            }
        }

        return outputImage
    }
}
