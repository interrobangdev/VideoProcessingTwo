//
//  VideoSource.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 4/22/24.
//

import Foundation
import CoreMedia

public class VideoSource: Source {
    var lastFrame: Frame?
    var currentFrame: Frame?

    var reader: MovieReader?
    let url: URL
    public var trackID: CMPersistentTrackID?

    public var naturalSize: CGSize {
        return currentFrame?.size ?? CGSize(width: 1920, height: 1080)
    }

    public var duration: Double {
        return reader?.duration ?? 0.0
    }

    public init(movieFileUrl: URL) {
        url = movieFileUrl
        self.trackID = nil

        setupReader(movieFileURL: movieFileUrl)
    }

    public init(url: URL) {
        self.url = url
        self.trackID = nil
        setupReader(movieFileURL: url)
    }

    public init(url: URL, trackID: CMPersistentTrackID) {
        self.url = url
        self.trackID = trackID
        // Don't setup reader when using video composition with trackID
    }

    func setupReader(movieFileURL: URL) {
        // Only setup reader if we're not using AVVideoComposition (trackID is nil)
        guard trackID == nil else { return }

        self.reader = MovieReader(url: movieFileURL)

        let success = reader?.setupReader()

        if let frame = reader?.getNextPixelBuffer() {
            lastFrame = frameFromVideoReaderFrame(frame: frame)
        }
        if let frm = reader?.getNextPixelBuffer() {
            currentFrame = frameFromVideoReaderFrame(frame: frm)
        }
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]? = nil) -> (any Frame)? {
        // If we have a trackID, get the frame from the provided dictionary
        if let trackID = trackID, let framesByTrackID = framesByTrackID, let sourceFrame = framesByTrackID[trackID] {
            return VideoFrame(pixelBuffer: sourceFrame, time: cmTime)
        }

        // Otherwise use MovieReader (asset reader mode)
        guard reader != nil else { return nil }

        let loopedTime = cmTime.seconds.remainder(dividingBy: reader?.duration ?? 1.0).cmTime()
        guard let lf = lastFrame,
              let cf = currentFrame else { return nil }
        if loopedTime >= lf.time && loopedTime < cf.time {
            return lf
        } else {
            lastFrame = currentFrame
            if let frame = reader?.getNextPixelBuffer() {
                currentFrame = frameFromVideoReaderFrame(frame: frame)
                return currentFrame
            } else {
                setupReader(movieFileURL: url)
                return lastFrame
            }
        }
    }

    func frameFromVideoReaderFrame(frame: VideoReaderFrame) -> VideoFrame {
        return VideoFrame(pixelBuffer: frame.pixelBuffer, time: frame.timeStamp)
    }
}
