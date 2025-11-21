//
//  CameraSource.swift
//  VideoProcessingTwo
//
//  A Source that provides live camera frames
//

import Foundation
import AVFoundation
import CoreMedia
import CoreImage

public protocol CameraSourceDelegate: NSObjectProtocol {
    func didReceiveFrame(frame: Frame)
}

public class CameraSource: NSObject, Source {
    public let cameraManager: CameraManager
    public weak var delegate: CameraSourceDelegate?
    private var lastFrame: Frame?

    /// When this camera source starts playing in the composition (in seconds)
    public var compositionStartTime: Double = 0.0

    /// How long this camera source plays in the composition (in seconds)
    public var duration: Double = .infinity

    /// Not used for live camera - always 0
    public var sourceStartTime: Double = 0.0

    /// Natural size of the camera frames
    public var naturalSize: CGSize = CGSize(width: 1920, height: 1080)
    
    private var cameraStartTimeStamp: CMTime?

    public init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        super.init()
        
        self.cameraManager.delegate = self
    }
    
    public func startCamera() {
        cameraManager.start()
    }
    

    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> Frame? {
        // Check if we're in the active time window
        let compositionTime = CMTimeGetSeconds(cmTime)
        guard compositionTime >= compositionStartTime else {
            return nil
        }

        // For infinite duration, always return a frame if available
        if duration.isInfinite {
            // Return the last captured frame if available
            if let frame = lastFrame {
                return frame
            }
        } else {
            // Check if still within duration window
            guard compositionTime < compositionStartTime + duration else {
                return nil
            }
            // Return the last captured frame if available
            if let frame = lastFrame {
                return frame
            }
        }

        return nil
    }
}

extension CameraSource: CameraManagerDelegate {
    public func didOutputFrame(frame: any Frame) {
        if cameraStartTimeStamp == 0.0.cmTime() {
            cameraStartTimeStamp = frame.time
        }
        
        let timeStamp = frame.time - (cameraStartTimeStamp ?? 0.0.cmTime())
        if let pb = frame.cvPixelRepresentation() {
            let newFrame = VideoFrame(pixelBuffer: pb, time: timeStamp)
            
            lastFrame = newFrame
            naturalSize = frame.size
            
            delegate?.didReceiveFrame(frame: newFrame)
        }
    }
    
    public func didOutputPhotoFrame(photo: CIImage) {
//        No-Op
    }
}
