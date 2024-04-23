//
//  MovieRecorder.swift
//  KNXN
//
//  Created by Jake Gundersen on 5/2/19.


import UIKit
import AVFoundation

public class MovieWriter: NSObject {
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    
    private var pixelBufferAdapter: AVAssetWriterInputPixelBufferAdaptor?
    
    private var writerQueue = DispatchQueue(label: "com.VideoProcessing.videoWriterQueue")
    
    var outputURL: URL
    var writerStarted = false
    var size: CGSize = .zero
    
    var status: AVAssetWriter.Status? {
        get {
            return assetWriter?.status
        }
    }
    
    public init(url: URL, size: CGSize, transform: CGAffineTransform) {
        outputURL = url
        super.init()
        
        let success = setupWriter(url: url, size: size, transform: transform)
        if !success {
            print("Video Writer setup failed")
        }
    }
    
    func setupWriter(url: URL, size: CGSize, transform: CGAffineTransform) -> Bool {
        self.size = size
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            let compressionDict: [String: Any] = [
                AVVideoAverageBitRateKey: NSNumber(integerLiteral: 8000000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel as String,
            ]
            
            let videoOutputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
                AVVideoCompressionPropertiesKey: compressionDict
            ]
            
            let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
            assetWriterInput.expectsMediaDataInRealTime = false
            
            assetWriter = writer
            assetWriterVideoInput = assetWriterInput
            assetWriterVideoInput?.transform = transform
            
            if writer.canAdd(assetWriterInput) {
                writer.add(assetWriterInput)
            }
            
            let pixelAdapter = pixelAdapterForVideoInput(videoInput: assetWriterInput, size: size)
            pixelBufferAdapter = pixelAdapter
        } catch let e {
            print("Error setting up asset writer \(e)")
            return false
        }
        return true
    }
    
    public func startWriter() {
        writerQueue.async { [weak self] in
            guard let s = self,
                let aw = s.assetWriter else { return }
            
            if !aw.startWriting() {
                print("Failure to start asset writer")
            }
        }
    }
    
    public func appendFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        writerQueue.async { [weak self] in
            guard let s = self,
                let aw = s.assetWriter,
                let vi = s.assetWriterVideoInput,
                let pixelAdapter = s.pixelBufferAdapter else {
                    return
            }
            
            if !s.writerStarted {
                aw.startSession(atSourceTime: time)
                s.writerStarted = true
            }
            
            if aw.status == .writing, vi.isReadyForMoreMediaData {
                if !pixelAdapter.append(pixelBuffer, withPresentationTime: time) {
                    print("Failed to append buffer at time \(CMTimeGetSeconds(time))")
                    return
                }
            }
        }
    }
    
    public func finishWriting(completion: @escaping (_ success: Bool) -> ()) {
        writerQueue.async { [weak self] in
            guard let s = self,
            let aw = s.assetWriter else {
                print("Failed to get assetWriter")
                completion(false)
                return
            }
            
            if aw.status != .writing {
                print("Cannot call finish writing if the status of the asset writer isn't 'Writing'")
                completion(false)
                return
            }
            
            aw.finishWriting {
                if aw.status == .failed {
                    print("Failed to completion recording \(String(describing: aw.error))")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }
    
    public func getPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        guard let adapter = pixelBufferAdapter,
            let pool = adapter.pixelBufferPool else {
                return nil
        }
        
        let success = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        
        if success != kCVReturnSuccess {
            print("Failed to create pixel buffer with code \(success)")
        }
        
        return pixelBuffer
    }
    
    private func pixelAdapterForVideoInput(videoInput: AVAssetWriterInput, size: CGSize) -> AVAssetWriterInputPixelBufferAdaptor {
        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        
        return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: sourceAttributes)
    }
}
