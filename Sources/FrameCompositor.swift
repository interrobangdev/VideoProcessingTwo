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
    private var videoWriter: MovieWriter?
    private var gifWriter: GIFWriter?
    
    public init() {}
    
    public func exportScene(scene: VideoScene, outputType: Composition.OutputType, outputURL: URL, frameCallback: FrameCallback, completion: @escaping (Bool) -> ()) {
        if outputType == .gif {
            let frameCount = Int(scene.duration * scene.frameRate)
            
            exportGIF(scene: scene, frameCount: frameCount, outputURL: outputURL, frameCallback: frameCallback, completion: { success in
                completion(success)
            })

        } else if outputType == .video {
            exportVideo(scene: scene, outputURL: outputURL, frameCallback: frameCallback, completion: { success in
                completion(success)
            })
        }
    }
    
    public func exportVideo(scene: VideoScene, outputURL: URL, frameCallback: FrameCallback, completion: @escaping (Bool) -> ()) {

        videoWriter = MovieWriter(url: outputURL, size: scene.size, transform: .identity)
        videoWriter?.startWriter()

        generateFrames(scene: scene, compositionTimeOffset: 0.0, realTime: false, frameCallback: { [weak self] (image, frameTime) in
            autoreleasepool {

                if let pixelBuffer = self?.videoWriter?.getPixelBuffer() {
                    MetalEnvironment.shared.context.render(image, to: pixelBuffer)

                    self?.videoWriter?.appendFrame(pixelBuffer: pixelBuffer, time: frameTime.cmTime(), completion: {
                    })
                }

                frameCallback(image, frameTime)
            }
        }, completion: { [weak self] (success) in
            self?.videoWriter?.finishWriting(completion: { success in
                print("success writing file \(success)")
                completion(success)
            })
        })
    }
    
    public func exportGIF(scene: VideoScene, frameCount: Int, outputURL: URL, frameCallback: FrameCallback, completion: (Bool) -> ()) {
        gifWriter = GIFWriter(url: outputURL, frameCount: frameCount)
        
        var previousTime = 0.0
        generateFrames(scene: scene, compositionTimeOffset: 0.0, realTime: false, frameCallback: { [weak self] (image, frameTime) in
            
            if let cgImg = MetalEnvironment.shared.context.createCGImage(image, from: image.extent) {
                
                let delay = frameTime - previousTime
                self?.gifWriter?.addFrame(image: cgImg, delay: delay)

                previousTime = frameTime
            }
            
            frameCallback(image, frameTime)
        }, completion: { [weak self] (success) in
            self?.gifWriter?.finalize()
            completion(success)
        })
    }
    
    public func generateFrames(scene: VideoScene, compositionTimeOffset: Double, realTime: Bool, frameCallback: FrameCallback, completion: CompletionCallback) {
        let frameCount = Int(scene.duration * scene.frameRate)

        let startTime = CFAbsoluteTimeGetCurrent()
        var renderTime = 0.0
        var callbackTime = 0.0

        for i in 0..<frameCount {
            autoreleasepool {
                let frameTime = Double(i) * (1.0 / scene.frameRate)

                let renderStart = CFAbsoluteTimeGetCurrent()
                if let outputImage = scene.group.renderGroup(frameTime: frameTime, compositionTimeOffset: compositionTimeOffset) {
                    renderTime += CFAbsoluteTimeGetCurrent() - renderStart

                    let callbackStart = CFAbsoluteTimeGetCurrent()
                    frameCallback(outputImage, frameTime)
                    callbackTime += CFAbsoluteTimeGetCurrent() - callbackStart
                }
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("Export timing - Total: \(totalTime)s, Render: \(renderTime)s, Callback: \(callbackTime)s, Frames: \(frameCount)")

        completion(true)
    }
}
