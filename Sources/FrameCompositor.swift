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
        print(
            "[FrameCompositor] exportVideo start output=\(outputURL.path) " +
            "size=\(scene.size.width)x\(scene.size.height) duration=\(scene.duration)s fps=\(scene.frameRate)"
        )
        videoWriter = MovieWriter(url: outputURL, size: scene.size, transform: .identity)
        videoWriter?.startWriter()

        generateFrames(scene: scene, compositionTimeOffset: 0.0, realTime: false, frameCallback: { [weak self] (image, frameTime) in
            autoreleasepool {
                if let pixelBuffer = self?.videoWriter?.getPixelBuffer() {
                    MetalEnvironment.shared.context.render(image, to: pixelBuffer)

                    // Apply backpressure so export doesn't enqueue an unbounded number
                    // of pending frames and get killed for memory pressure.
                    let appendSemaphore = DispatchSemaphore(value: 0)
                    self?.videoWriter?.appendFrame(pixelBuffer: pixelBuffer, time: frameTime.cmTime(), completion: {
                        appendSemaphore.signal()
                    })
                    appendSemaphore.wait()
                } else {
                    print("[FrameCompositor] Failed to allocate pixel buffer at time=\(frameTime)s")
                }

                frameCallback(image, frameTime)
            }
        }, completion: { [weak self] (success) in
            print("[FrameCompositor] frame generation completed success=\(success)")
            self?.videoWriter?.finishWriting(completion: { success in
                let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                print(
                    "[FrameCompositor] writer finished success=\(success) " +
                    "fileExists=\(fileExists) fileSize=\(fileSize) output=\(outputURL.path)"
                )
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
        var renderedFrameCount = 0
        var skippedFrameCount = 0
        let progressInterval = max(1, frameCount / 20)

        for i in 0..<frameCount {
            autoreleasepool {
                let frameTime = Double(i) * (1.0 / scene.frameRate)

                let renderStart = CFAbsoluteTimeGetCurrent()
                if let outputImage = scene.renderScene(frameTime: frameTime, compositionTimeOffset: compositionTimeOffset) {
                    renderTime += CFAbsoluteTimeGetCurrent() - renderStart
                    renderedFrameCount += 1

                    let callbackStart = CFAbsoluteTimeGetCurrent()
                    frameCallback(outputImage, frameTime)
                    callbackTime += CFAbsoluteTimeGetCurrent() - callbackStart
                } else {
                    skippedFrameCount += 1
                    print("[FrameCompositor] No output image for frameIndex=\(i) time=\(frameTime)s")
                }

                if i == 0 || i == frameCount - 1 || i % progressInterval == 0 {
                    let progress = frameCount > 0 ? Double(i + 1) / Double(frameCount) : 1.0
                    let percent = Int((progress * 100.0).rounded(.down))
                    print(
                        "[FrameCompositor] frame progress=\(percent)% " +
                        "frameIndex=\(i + 1)/\(frameCount) rendered=\(renderedFrameCount) skipped=\(skippedFrameCount)"
                    )
                }
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print(
            "[FrameCompositor] Export timing total=\(totalTime)s render=\(renderTime)s " +
            "callback=\(callbackTime)s requestedFrames=\(frameCount) renderedFrames=\(renderedFrameCount) skippedFrames=\(skippedFrameCount)"
        )

        completion(true)
    }
}
