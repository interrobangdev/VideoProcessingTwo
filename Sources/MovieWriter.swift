//
//  MovieRecorder.swift
//  KNXN
//
//  Created by Jake Gundersen on 5/2/19.


//import UIKit
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
        
        // Validate size
        if size.width <= 0 || size.height <= 0 {
            print("Invalid video size: \(size)")
            return false
        }
        
        // Ensure size is even numbers (H.264 requirement)
        let adjustedSize = CGSize(
            width: floor(size.width / 2) * 2,
            height: floor(size.height / 2) * 2
        )
        
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            let compressionDict: [String: Any] = [
                AVVideoAverageBitRateKey: NSNumber(integerLiteral: 8000000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel as String,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCAVLC,
                AVVideoAllowFrameReorderingKey: false
            ]
            
            let videoOutputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(adjustedSize.width),
                AVVideoHeightKey: Int(adjustedSize.height),
                AVVideoCompressionPropertiesKey: compressionDict
            ]
            
            let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
            assetWriterInput.expectsMediaDataInRealTime = false
            
            assetWriter = writer
            assetWriterVideoInput = assetWriterInput
            assetWriterVideoInput?.transform = transform
            
            if writer.canAdd(assetWriterInput) {
                writer.add(assetWriterInput)
                print("Successfully added asset writer input")
            } else {
                print("Failed to add asset writer input")
                return false
            }
            
            let pixelAdapter = pixelAdapterForVideoInput(videoInput: assetWriterInput, size: adjustedSize)
            pixelBufferAdapter = pixelAdapter
            
            print("MovieWriter setup completed successfully")
        } catch let e {
            print("Error setting up asset writer: \(e)")
            print("URL: \(url)")
            print("File exists: \(FileManager.default.fileExists(atPath: url.path))")
            return false
        }
        return true
    }
    
    public func startWriter() {
        writerQueue.async { [weak self] in
            guard let s = self,
                let aw = s.assetWriter else { 
                print("Failed to get self or assetWriter in startWriter")
                return 
            }

            if !aw.startWriting() {
                print("Failure to start asset writer")
                print("Asset writer status: \(aw.status)")
                if let error = aw.error {
                    print("Asset writer error: \(error)")
                }
            } else {
                print("Asset writer started successfully")
                print("Asset writer status after starting: \(aw.status)")
            }
        }
    }
    
    public func appendFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        writerQueue.async { [weak self] in
            guard let s = self,
                let aw = s.assetWriter,
                let vi = s.assetWriterVideoInput,
                let pixelAdapter = s.pixelBufferAdapter else {
                    print("Failed to get components in appendFrame")
                    return
            }
            
            if !s.writerStarted {
                print("Starting session at time: \(CMTimeGetSeconds(time))")
                aw.startSession(atSourceTime: time)
                s.writerStarted = true
            }
            
            if aw.status == .writing {
                if vi.isReadyForMoreMediaData {
                    if !pixelAdapter.append(pixelBuffer, withPresentationTime: time) {
                        print("Failed to append buffer at time \(CMTimeGetSeconds(time))")
                        print("Asset writer status: \(aw.status)")
                        if let error = aw.error {
                            print("Asset writer error: \(error)")
                        }
                        return
                    } else {
//                        print("Successfully appended frame at time \(CMTimeGetSeconds(time))")
                    }
                } else {
                    print("Video input not ready for more data at time \(CMTimeGetSeconds(time))")
                }
            } else {
                print("Asset writer not in writing state: \(aw.status) at time \(CMTimeGetSeconds(time))")
            }
        }
    }
    
    public func finishWriting(completion: @escaping (_ success: Bool) -> ()) {
        guard let aw = self.assetWriter else {
            print("Failed to get assetWriter in finishWriting - assetWriter is nil")
            completion(false)
            return
        }
        
        if aw.status != .writing {
            print("Cannot call finish writing if the status of the asset writer isn't 'Writing', current status: \(aw.status)")
            if let error = aw.error {
                print("Asset writer error: \(error)")
            }
            completion(false)
            return
        }
        
        // Mark the input as finished on the writer queue
        writerQueue.async { [weak self] in
            self?.assetWriterVideoInput?.markAsFinished()
            
            self?.assetWriter?.finishWriting {
                completion(true)
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
