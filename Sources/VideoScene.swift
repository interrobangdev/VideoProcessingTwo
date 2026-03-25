//
//  VideoScene.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import AVFoundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct Transition {
    public enum TransitionType {
        case none
        case fade
    }
    
    public var type: TransitionType
    public var duration: Double
    
    public func transitionFrames(frameA: Frame, frameB: Frame, progressPercent: Double) -> Frame {
        return frameA
    }
}



public class VideoScene {
    public let id = UUID().uuidString
    public var duration: Double
    public var frameRate: Double

    public var group: LayerGroup
    var transition: Transition

    public var asset: AVURLAsset?
    public var size: CGSize
    public var bodyPoseParameterDriver: BodyPoseFilterParameterDriver?

    public enum AssetType: String {
        case image
        case video
        case gif
        case text
    }

    public init(id: String = UUID().uuidString, duration: Double, frameRate: Double, transition: Transition? = nil, size: CGSize = CGSize(width: 1200, height: 675)) {
        self.duration = duration
        self.frameRate = frameRate
        self.group = LayerGroup(groups: [], layers: [], filters: [], mask: nil)
        self.transition = transition ?? Transition(type: .none, duration: 0.0)
        self.size = size
        self.bodyPoseParameterDriver = nil
    }

    public func makeSceneFilename() -> String {
        return "\(id).mp4"
    }

    func loadSceneAsset(containingFolder: String) -> AVURLAsset {
        let path = "\(containingFolder)/\(makeSceneFilename())"
        let url = URL(fileURLWithPath: path)

        return AVURLAsset(url: url)
    }
    
    public func renderScene(frameTime: Double, compositionTimeOffset: Double, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]? = nil) -> CIImage? {
        let inputImage = CIImage.black.cropped(to: CGRect(origin: .zero, size: size))
        return group.renderGroup(
            frameTime: frameTime,
            compositionTimeOffset: compositionTimeOffset,
            inputImage: inputImage,
            framesByTrackID: framesByTrackID,
            bodyPoseParameterDriver: bodyPoseParameterDriver
        )
    }
    
    public func getGroup(layerIndex: LayerObjectIndex, create: Bool) -> LayerGroup? {
        var group = self.group
        for groupIndex in layerIndex.groupIndices {
            if group.groups.count > groupIndex {
                group = group.groups[groupIndex]
            } else {
                if create {
                    let groupCount = (groupIndex + 1) - group.groups.count
                    for _ in 0..<groupCount {
                        group.groups.append(LayerGroup.emptyGroup())
                    }
                    
                    group = group.groups[groupIndex]
                } else {
                    return nil
                }
            }
        }
        
        return group
    }
    
    public func getGroupLayer(layerIndex: LayerObjectIndex, create: Bool) -> Layer? {
        guard let group = getGroup(layerIndex: layerIndex, create: create) else { return nil }
        
        if group.layers.count > layerIndex.layerIndex {
            return group.layers[layerIndex.layerIndex]
        } else {
            if create {
                let layerCount = (layerIndex.layerIndex + 1) - group.layers.count
                for _ in 0..<layerCount {
                    group.layers.append(Layer(surfaces: []))
                }
                
                return group.layers[layerIndex.layerIndex]
            }
        }
        
        return nil
    }
    
    public func addAsset(atLayerIndex: LayerObjectIndex, type: AssetType, frame: CGRect, rotation: Double = 0.0, assetURL: URL, text: String) -> Bool {
        
        guard let layer = getGroupLayer(layerIndex: atLayerIndex, create: true) else { return false }
        
        var source: Source?
        
        if type == .gif {
            if let data = try? Data(contentsOf: assetURL),
                let gifImage = GIFImage(gifData: data) {
                source = GIFImageSource(image: gifImage)
                
            }
        } else if type == .image {
            if let image = PlatformImage(contentsOfFile: assetURL.path),
                  let cgImage = image.cgImageRepresentation {
                      source = ImageSource(image: cgImage)
                  }
        } else if type == .video {
            let videoSource = VideoSource(movieFileUrl: assetURL)
            if let reader = videoSource.reader {
                videoSource.duration = reader.duration > 0 ? reader.duration : duration
                videoSource.sourceVideoDuration = reader.duration
                videoSource.naturalSize = reader.size
            } else {
                videoSource.duration = duration
            }
            source = videoSource
        } 
        
        if let source = source {
            let surface = Surface(source: source, frame: frame, rotation: rotation)
            layer.surfaces.append(surface)
            return true
        }
        
        return false
    }
}
