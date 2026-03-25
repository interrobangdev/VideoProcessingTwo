import Foundation
import CoreGraphics
import CoreMedia

/// A single detected body joint in normalized Vision coordinates.
public struct BodyPoseJoint {
    public let name: String
    public let normalizedLocation: CGPoint
    public let confidence: Float

    public init(name: String, normalizedLocation: CGPoint, confidence: Float) {
        self.name = name
        self.normalizedLocation = normalizedLocation
        self.confidence = confidence
    }

    /// Converts the normalized point to pixel coordinates.
    /// - Parameter topLeftOrigin: Set `true` for UIKit/AppKit view coordinates.
    public func point(in imageSize: CGSize, topLeftOrigin: Bool = true) -> CGPoint {
        let x = normalizedLocation.x * imageSize.width
        let yFactor = topLeftOrigin ? (1.0 - normalizedLocation.y) : normalizedLocation.y
        let y = yFactor * imageSize.height
        return CGPoint(x: x, y: y)
    }
}

/// A single detected person in a frame and all recognized joints for that person.
public struct BodyPosePerson {
    public let id: UUID
    public let jointsByName: [String: BodyPoseJoint]

    public init(id: UUID, jointsByName: [String: BodyPoseJoint]) {
        self.id = id
        self.jointsByName = jointsByName
    }

    public subscript(jointName: String) -> BodyPoseJoint? {
        jointsByName[jointName]
    }
}

/// Pose data for one video frame.
public struct BodyPoseFrame {
    public let time: CMTime
    public let imageSize: CGSize
    public let people: [BodyPosePerson]

    public init(time: CMTime, imageSize: CGSize, people: [BodyPosePerson]) {
        self.time = time
        self.imageSize = imageSize
        self.people = people
    }
}

/// Time-ordered body pose detections for an entire video.
public struct BodyPoseTimeline {
    public let sourceURL: URL
    public let duration: CMTime
    public let sampledFrameRate: Double
    public let frames: [BodyPoseFrame]

    public init(sourceURL: URL, duration: CMTime, sampledFrameRate: Double, frames: [BodyPoseFrame]) {
        self.sourceURL = sourceURL
        self.duration = duration
        self.sampledFrameRate = sampledFrameRate
        self.frames = frames
    }

    public func nearestFrame(to time: CMTime) -> BodyPoseFrame? {
        guard !frames.isEmpty else { return nil }
        let targetSeconds = CMTimeGetSeconds(time)
        guard targetSeconds.isFinite else { return frames.first }

        var nearest: BodyPoseFrame?
        var nearestDistance = Double.greatestFiniteMagnitude

        for frame in frames {
            let seconds = CMTimeGetSeconds(frame.time)
            guard seconds.isFinite else { continue }
            let distance = abs(seconds - targetSeconds)
            if distance < nearestDistance {
                nearest = frame
                nearestDistance = distance
            }
        }

        return nearest ?? frames.first
    }
}
