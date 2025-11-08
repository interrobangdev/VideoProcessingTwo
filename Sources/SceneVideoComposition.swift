//
//  SceneVideoComposition.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 10/31/25.
//

import AVFoundation
import CoreMedia
import CoreImage

/// Result of creating a scene video composition
public struct SceneCompositionResult {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVAudioMix?
}

/// Creates compositions with custom video compositing that applies filters from a VideoScene
public class SceneVideoComposition {

    /// Creates a composition with animated filters from a VideoScene
    /// - Parameters:
    ///   - scene: The VideoScene containing layers and animated filters
    /// - Returns: A SceneCompositionResult containing the composition, video composition, and audio mix
    public static func createComposition(scene: VideoScene) -> SceneCompositionResult? {
        // Use VideoCompositor to build the composition from the scene
        let compositor = VideoCompositor(scene: scene)

        let composition: AVMutableComposition
        do {
            composition = try compositor.buildComposition()
        } catch {
            return nil
        }

        // Create video composition with custom compositor
        let videoComposition = createVideoComposition(
            scene: scene,
            composition: composition,
            compositor: compositor
        )

        return SceneCompositionResult(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: nil
        )
    }

    private static func createVideoComposition(
        scene: VideoScene,
        composition: AVMutableComposition,
        compositor: VideoCompositor
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = scene.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = SceneVideoCompositor.self

        // Create a single instruction with all video track IDs
        let trackIDs = Array(compositor.sourceTrackIdToScene.keys)
        let instruction = SceneVideoCompositorInstruction(
            scene: scene,
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: composition.duration.seconds, preferredTimescale: 600)),
            trackIDs: trackIDs
        )

        videoComposition.instructions = [instruction]
        videoComposition.renderScale = 1.0

        return videoComposition
    }
}

// MARK: - Video Compositor

public class SceneVideoCompositor: NSObject, AVVideoCompositing {
    private let renderQueue = DispatchQueue(label: "com.videoprocessingtwo.scenecompositor", qos: .userInteractive)

    public var sourcePixelBufferAttributes: [String : Any]? {
        // Accept multiple formats - let AVFoundation choose what works
        // For yuv420p videos, it might convert to biplanar instead of BGRA
        return [
            String(kCVPixelBufferPixelFormatTypeKey): [
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelFormatType_32BGRA
            ] as [NSNumber]
        ]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
        ]
    }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Called when render context is set up
    }

    public func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            self.handleRequest(asyncVideoCompositionRequest)
        }
    }

    private func handleRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? SceneVideoCompositorInstruction else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "SceneVideoCompositor", code: -1))
            return
        }

        guard let trackIDNumber = instruction.requiredSourceTrackIDs?.first as? NSNumber else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "SceneVideoCompositor", code: -2))
            return
        }

        let trackID = trackIDNumber.int32Value

        guard let sourceFrame = asyncVideoCompositionRequest.sourceFrame(byTrackID: trackID) else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "SceneVideoCompositor", code: -3))
            return
        }

        let time = CMTimeGetSeconds(asyncVideoCompositionRequest.compositionTime)

        // Build a dictionary of frames by trackID for VideoSource instances
        var framesByTrackID: [CMPersistentTrackID: CVPixelBuffer] = [:]
        if let requiredTrackIDs = instruction.requiredSourceTrackIDs as? [NSNumber] {
            for numberValue in requiredTrackIDs {
                let tID = numberValue.int32Value
                if let frame = asyncVideoCompositionRequest.sourceFrame(byTrackID: tID) {
                    framesByTrackID[tID] = frame
                }
            }
        }

        // Convert source frame to CIImage (handles any pixel format)
        let sourceImage = CIImage(cvPixelBuffer: sourceFrame)

        // Render the scene at the current time, passing the frames dictionary to VideoSource instances
        if let outputImage = instruction.scene.group.renderGroup(frameTime: time, compositionTimeOffset: 0.0, framesByTrackID: framesByTrackID) {
            guard let pixelBuffer = asyncVideoCompositionRequest.renderContext.newPixelBuffer() else {
                asyncVideoCompositionRequest.finish(with: NSError(domain: "SceneVideoCompositor", code: -4))
                return
            }

            // Composite the rendered scene over/with the source image if needed
            // For now, just render the scene output
            MetalEnvironment.shared.context.render(outputImage, to: pixelBuffer)
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: pixelBuffer)
        } else {
            // Fallback to original frame
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: sourceFrame)
        }
    }
}

// MARK: - Compositor Instruction

public class SceneVideoCompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    public var timeRange: CMTimeRange
    public var enablePostProcessing: Bool = false
    public var containsTweening: Bool = true
    public var requiredSourceTrackIDs: [NSValue]?
    public var passthroughTrackID: CMPersistentTrackID {
        return kCMPersistentTrackID_Invalid
    }

    let scene: VideoScene

    init(scene: VideoScene, timeRange: CMTimeRange, trackID: CMPersistentTrackID) {
        self.scene = scene
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        super.init()
    }

    init(scene: VideoScene, timeRange: CMTimeRange, trackIDs: [CMPersistentTrackID]) {
        self.scene = scene
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
        super.init()
    }
}
