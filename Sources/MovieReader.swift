//
//  MovieReader.swift
//  testfritz
//
//  Created by Jake Gundersen on 6/27/20.
//  Copyright © 2020 Interrobang Software. All rights reserved.
//

import AVFoundation

public struct VideoReaderFrame {
    let frameId: String
    let readerId: String
    let pixelBuffer: CVPixelBuffer
    let timeStamp: CMTime
}

public class MovieReader {
    let id = UUID().uuidString
    let url: URL
    var assetReader: AVAssetReader?
    var videoTrackOutput: AVAssetReaderTrackOutput?
    var audioTrackOutput: AVAssetReaderTrackOutput?
    
    var duration: Double = 0.0
    var frameRate: Double = 0.0
    var size: CGSize = .zero
    var transform: CGAffineTransform = .identity
    
    public init(url: URL) {
        self.url = url
        let _ = setupReader()
    }
    
    public func setupReader() -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            assetReader = try AVAssetReader(asset: asset)
        } catch let e {
            print("Error setting up asset reader \(e)")
            return false
        }
        
        guard let track = asset.tracks(withMediaType: .video).first else { return false }
        let outputSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings as [String : Any])
        videoTrackOutput = trackOutput
        
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let audioOutputSettings: [String : Any] = [
                AVFormatIDKey:   Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16
            ]
            audioTrackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
        }
        
        duration = asset.duration.seconds
        frameRate = Double(track.nominalFrameRate)
        size = track.naturalSize
        transform = track.preferredTransform
        
        assetReader?.add(trackOutput)
        
        if let ato = audioTrackOutput {
            assetReader?.add(ato)
        }
        
        assetReader?.startReading()
        return true
    }
    
    public func getNextAudioBuffer() -> CMSampleBuffer? {
        if let ato = audioTrackOutput,
           let sampleBuffer = ato.copyNextSampleBuffer() {
            return sampleBuffer
        }
        return nil 
    }
    
    public func getNextPixelBuffer() -> VideoReaderFrame? {
        if let to = videoTrackOutput,
            let sampleBuffer = to.copyNextSampleBuffer(),
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            let videoF = VideoReaderFrame(frameId: UUID().uuidString, readerId: id, pixelBuffer: pixelBuffer, timeStamp: time)
            return videoF
        }
        
        return nil
    }
}
