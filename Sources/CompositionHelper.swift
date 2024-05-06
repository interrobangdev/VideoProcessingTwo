//
//  CompositionHelper.swift
//
//
//  Created by Jake Gundersen on 4/26/24.
//

import AVFoundation

public struct CompositionPlayerInfo {
    public let id: String
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix?
}

public class CompositionHelper {
    var exportSession: AVAssetExportSession?
    var exportSessionTimer: Timer?
    
    public init(exportSession: AVAssetExportSession? = nil) {
        self.exportSession = exportSession
    }
    
    public class func makeComposition(composition: Composition, containingFolder: String) -> CompositionPlayerInfo {
        let comp = AVMutableComposition()
        
        let trackOne = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let trackTwo = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        for scene in composition.scenes {
            scene.asset = scene.loadSceneAsset(containingFolder: containingFolder)
        }
        
        var startTime = 0.0
        
        for i in 0..<composition.scenes.count {
            let scene = composition.scenes[i]
            
            let mutableTrack = i % 2 == 0 ? trackOne : trackTwo
            
            if let videoTrack = scene.asset?.tracks(withMediaType: .video).first {
                
                let timeRange = CMTimeRange(start: .zero, end:  scene.duration.cmTime())
                do {
                    try mutableTrack?.insertTimeRange(timeRange, of: videoTrack, at: startTime.cmTime())
                } catch let e {
                    print("Error inserting track \(e)")
                }
                
                startTime = (startTime + scene.duration) - scene.transition.duration
            }
        }
        
        let videoComposition = AVMutableVideoComposition(propertiesOf: comp)
        videoComposition.renderSize = composition.renderSize
        
        return CompositionPlayerInfo(id: composition.id, composition: comp, videoComposition: videoComposition, audioMix: nil)
    }
    
    public func exportComposition(outputURL: URL, compositionPlayerInfo: CompositionPlayerInfo, progress: ((String, Double) -> ())?, completion: @escaping (URL?, Error?) -> ()) {
        
        exportSession = AVAssetExportSession(asset: compositionPlayerInfo.composition, presetName: AVAssetExportPresetHighestQuality)
        
        exportSession?.videoComposition = compositionPlayerInfo.videoComposition
        exportSession?.audioMix = compositionPlayerInfo.audioMix
        
        exportSession?.outputFileType = .mp4
        exportSession?.outputURL = outputURL
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.exportSessionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] (timer) in

                guard let progressVal = self?.exportSession?.progress else {
                    timer.invalidate()
                    self?.exportSessionTimer = nil
                    
                    return
                }
                
                progress?(compositionPlayerInfo.id, Double(progressVal))
                
                if progressVal > 0.97 {
                    timer.invalidate()
                    self?.exportSessionTimer = nil
                }
            })
        }
        
        exportSession?.exportAsynchronously { [weak self] in
            if let error = self?.exportSession?.error {
                print("Error exporting \(error)")
                completion(nil, error)
            }
            
            completion(outputURL, nil)
        }
    }
}
