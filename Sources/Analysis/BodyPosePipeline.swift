import Foundation

/// High-level helpers for attaching pose-driven filtering to a scene.
public enum BodyPosePipeline {
    @discardableResult
    public static func attachPoseDriver(
        to scene: VideoScene,
        sourceVideoURL: URL,
        analysisConfiguration: BodyPoseVideoAnalysisConfiguration = BodyPoseVideoAnalysisConfiguration(),
        personSelection: BodyPosePersonSelection = .mostConfident
    ) throws -> BodyPoseFilterParameterDriver {
        let timeline = try BodyPoseVideoAnalyzer().analyze(
            videoURL: sourceVideoURL,
            configuration: analysisConfiguration
        )

        let driver = BodyPoseFilterParameterDriver(
            timeline: timeline,
            personSelection: personSelection
        )
        scene.bodyPoseParameterDriver = driver
        return driver
    }

    @discardableResult
    public static func attachPoseDriver(
        to scene: VideoScene,
        timeline: BodyPoseTimeline,
        personSelection: BodyPosePersonSelection = .mostConfident
    ) -> BodyPoseFilterParameterDriver {
        let driver = BodyPoseFilterParameterDriver(
            timeline: timeline,
            personSelection: personSelection
        )
        scene.bodyPoseParameterDriver = driver
        return driver
    }
}
