import Foundation
import Vision
import ImageIO
import CoreMedia
import CoreImage

public enum BodyPoseEstimationError: Error {
    case missingImageRepresentation
    case requestFailed(Error)
}

public struct BodyPoseEstimationConfiguration {
    public var maximumHumanCount: Int
    public var minimumConfidence: Float
    public var orientation: CGImagePropertyOrientation

    public init(
        maximumHumanCount: Int = 1,
        minimumConfidence: Float = 0.2,
        orientation: CGImagePropertyOrientation = .up
    ) {
        self.maximumHumanCount = max(1, maximumHumanCount)
        self.minimumConfidence = minimumConfidence
        self.orientation = orientation
    }
}

/// Detects body joints from individual frames.
public class BodyPoseEstimator {
    public var configuration: BodyPoseEstimationConfiguration

    public init(configuration: BodyPoseEstimationConfiguration = BodyPoseEstimationConfiguration()) {
        self.configuration = configuration
    }

    public func estimate(
        frame: Frame,
        at time: CMTime? = nil,
        orientation: CGImagePropertyOrientation? = nil
    ) throws -> BodyPoseFrame {
        guard let image = frame.ciImageRepresentation() else {
            throw BodyPoseEstimationError.missingImageRepresentation
        }

        return try estimate(
            image: image,
            imageSize: frame.size,
            at: time ?? frame.time,
            orientation: orientation
        )
    }

    public func estimate(
        image: CIImage,
        imageSize: CGSize? = nil,
        at time: CMTime = .zero,
        orientation: CGImagePropertyOrientation? = nil
    ) throws -> BodyPoseFrame {
        let request = VNDetectHumanBodyPoseRequest()

        let handler = VNImageRequestHandler(
            ciImage: image,
            orientation: orientation ?? configuration.orientation
        )

        do {
            try handler.perform([request])
        } catch {
            throw BodyPoseEstimationError.requestFailed(error)
        }

        let people = (request.results ?? [])
            .prefix(configuration.maximumHumanCount)
            .compactMap { observation in
            makePerson(from: observation)
        }

        return BodyPoseFrame(
            time: time,
            imageSize: imageSize ?? image.extent.size,
            people: people
        )
    }

    private func makePerson(from observation: VNHumanBodyPoseObservation) -> BodyPosePerson? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            return nil
        }

        var jointsByName: [String: BodyPoseJoint] = [:]
        for (jointName, point) in recognizedPoints where point.confidence >= configuration.minimumConfidence {
            let name = jointName.rawValue.rawValue
            jointsByName[name] = BodyPoseJoint(
                name: name,
                normalizedLocation: point.location,
                confidence: point.confidence
            )
        }

        return BodyPosePerson(id: observation.uuid, jointsByName: jointsByName)
    }
}
