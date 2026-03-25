import Foundation
import AVFoundation
import CoreMedia
import ImageIO

public enum BodyPoseVideoAnalysisError: Error {
    case videoTrackNotFound
    case failedToCreateAssetReader(Error)
    case unableToAddTrackOutput
    case failedToStartReading(Error?)
    case readerFailed(Error?)
}

public struct BodyPoseVideoAnalysisConfiguration {
    /// Frames sampled per second. `nil` means process every source frame.
    public var sampleRate: Double?
    /// Limit analysis to the first `maximumDuration` seconds.
    public var maximumDuration: Double?
    /// Optional override; when nil, orientation is inferred from track transform.
    public var orientation: CGImagePropertyOrientation?

    public init(
        sampleRate: Double? = nil,
        maximumDuration: Double? = nil,
        orientation: CGImagePropertyOrientation? = nil
    ) {
        if let sampleRate, sampleRate > 0 {
            self.sampleRate = sampleRate
        } else {
            self.sampleRate = nil
        }
        self.maximumDuration = maximumDuration
        self.orientation = orientation
    }
}

/// Reads a video and emits a timeline of body pose detections.
public class BodyPoseVideoAnalyzer {
    public let estimator: BodyPoseEstimator

    public init(estimator: BodyPoseEstimator = BodyPoseEstimator()) {
        self.estimator = estimator
    }

    public func analyze(
        videoURL: URL,
        configuration: BodyPoseVideoAnalysisConfiguration = BodyPoseVideoAnalysisConfiguration()
    ) throws -> BodyPoseTimeline {
        let asset = AVURLAsset(url: videoURL)

        guard let track = asset.tracks(withMediaType: .video).first else {
            throw BodyPoseVideoAnalysisError.videoTrackNotFound
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw BodyPoseVideoAnalysisError.failedToCreateAssetReader(error)
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw BodyPoseVideoAnalysisError.unableToAddTrackOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw BodyPoseVideoAnalysisError.failedToStartReading(reader.error)
        }

        let orientation = configuration.orientation ?? Self.orientation(from: track.preferredTransform)
        let sampleInterval: CMTime? = configuration.sampleRate.map {
            CMTime(seconds: 1.0 / $0, preferredTimescale: 600)
        }

        var nextSampleTime = CMTime.zero
        var frames: [BodyPoseFrame] = []

        while let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            if let maximumDuration = configuration.maximumDuration,
               CMTimeGetSeconds(sampleTime) > maximumDuration {
                break
            }

            if sampleInterval != nil, CMTimeCompare(sampleTime, nextSampleTime) < 0 {
                continue
            }

            let frame = VideoFrame(pixelBuffer: pixelBuffer, time: sampleTime)
            let poseFrame = try estimator.estimate(
                frame: frame,
                at: sampleTime,
                orientation: orientation
            )
            frames.append(poseFrame)

            if let sampleInterval {
                nextSampleTime = CMTimeAdd(sampleTime, sampleInterval)
            }
        }

        if reader.status == .failed {
            throw BodyPoseVideoAnalysisError.readerFailed(reader.error)
        }

        let sampledFrameRate = configuration.sampleRate ?? max(Double(track.nominalFrameRate), 0.0)

        return BodyPoseTimeline(
            sourceURL: videoURL,
            duration: asset.duration,
            sampledFrameRate: sampledFrameRate,
            frames: frames
        )
    }

    private static func orientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let a = Int(round(transform.a))
        let b = Int(round(transform.b))
        let c = Int(round(transform.c))
        let d = Int(round(transform.d))

        switch (a, b, c, d) {
        case (0, 1, -1, 0):
            return .right
        case (0, -1, 1, 0):
            return .left
        case (-1, 0, 0, -1):
            return .down
        default:
            return .up
        }
    }
}
