//
//  VideoSource.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 4/22/24.
//

import Foundation
import AVFoundation
import CoreMedia

public class VideoSource: Source {
    var lastFrame: Frame?
    var currentFrame: Frame?

    var reader: MovieReader?
    let url: URL
    public var trackID: CMPersistentTrackID?

    /// When this video starts playing in the composition (in seconds)
    public var compositionStartTime: Double = 0.0

    /// How long this video plays in the composition (in seconds)
    public var duration: Double = 10.0

    /// What time in the source video to start from (in seconds)
    public var sourceStartTime: Double = 0.0

    /// Natural size of the video
    public var naturalSize: CGSize = CGSize(width: 1920, height: 1080)

    /// Duration of the source video in seconds
    public var sourceVideoDuration: Double = 0.0

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

    /// Initialize for use with AVVideoComposition (no MovieReader created)
    /// - Parameters:
    ///   - url: URL to the video file
    ///   - useComposition: Set to true to skip MovieReader initialization (for AVVideoComposition mode)
    public init(url: URL, useComposition: Bool) {
        self.url = url
        self.trackID = nil
        // Don't setup reader when using video composition mode
        if !useComposition {
            setupReader(movieFileURL: url)
        }
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

        if let frame = reader?.getNextPixelBuffer() {
            lastFrame = frameFromVideoReaderFrame(frame: frame)
        }
        if let frm = reader?.getNextPixelBuffer() {
            currentFrame = frameFromVideoReaderFrame(frame: frm)
        }
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]? = nil) -> (any Frame)? {
        let compositionTimeSeconds = cmTime.seconds

        // Check if we're within the visible time window for this source
        let startTime = compositionStartTime
        let endTime = compositionStartTime + duration

        // If composition time is outside our window, return nil
        if compositionTimeSeconds < startTime || compositionTimeSeconds >= endTime {
            return nil
        }

        // If we have a trackID, get the frame from the provided dictionary
        if let trackID = trackID, let framesByTrackID = framesByTrackID, let sourceFrame = framesByTrackID[trackID] {
            return VideoFrame(pixelBuffer: sourceFrame, time: cmTime)
        }

        // Otherwise use MovieReader (asset reader mode)
        guard let reader else { return nil }

        let sourceDuration = max(reader.duration, sourceVideoDuration, 1.0 / 600.0)
        let frameDuration = 1.0 / max(reader.frameRate, 30.0)
        let sourceTime = max(0.0, compositionTimeSeconds - compositionStartTime + sourceStartTime)
        let shouldLoopSource = duration > sourceDuration + frameDuration
        let targetTimeSeconds: Double

        if shouldLoopSource {
            targetTimeSeconds = sourceTime.truncatingRemainder(dividingBy: sourceDuration)
        } else {
            targetTimeSeconds = min(sourceTime, max(sourceDuration - frameDuration, 0.0))
        }

        let targetTime = targetTimeSeconds.cmTime()

        if let lf = lastFrame, targetTime < lf.time {
            setupReader(movieFileURL: url)
        }

        guard let lf = lastFrame,
              let cf = currentFrame else { return nil }

        if targetTime >= lf.time && targetTime < cf.time {
            return lf
        }

        var previousFrame = lf
        var nextFrame = cf

        while targetTime >= nextFrame.time {
            previousFrame = nextFrame

            if let frame = self.reader?.getNextPixelBuffer() {
                nextFrame = frameFromVideoReaderFrame(frame: frame)
                continue
            }

            if shouldLoopSource {
                setupReader(movieFileURL: url)
                guard
                    let resetLastFrame = lastFrame,
                    let resetCurrentFrame = currentFrame
                else {
                    return previousFrame
                }

                previousFrame = resetLastFrame
                nextFrame = resetCurrentFrame
                continue
            }

            // Near EOF, hold on the final decoded frame instead of restarting the reader.
            lastFrame = previousFrame
            currentFrame = previousFrame
            return previousFrame
        }

        lastFrame = previousFrame
        currentFrame = nextFrame
        return previousFrame
    }

    func frameFromVideoReaderFrame(frame: VideoReaderFrame) -> VideoFrame {
        return VideoFrame(pixelBuffer: frame.pixelBuffer, time: frame.timeStamp)
    }

    /// Load video metadata (size and duration) asynchronously using AVURLAsset
    /// - Parameter completion: Called with success, size, and duration when metadata is loaded
    public func loadMetadata(completion: @escaping (Bool, CGSize?, Double?) -> Void) {
        let asset = AVURLAsset(url: url)

        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
            guard let self = self else {
                completion(false, nil, nil)
                return
            }

            // Check for load errors
            var error: NSError?
            let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
            let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)

            guard durationStatus == .loaded && tracksStatus == .loaded else {
                completion(false, nil, nil)
                return
            }

            // Get duration
            let duration = asset.duration.seconds
            self.sourceVideoDuration = duration

            // Get natural size from video track
            var size: CGSize?
            if let videoTrack = asset.tracks(withMediaType: .video).first {
                size = videoTrack.naturalSize
                self.naturalSize = size ?? CGSize(width: 1920, height: 1080)
            }

            completion(true, size, duration)
        }
    }
}
