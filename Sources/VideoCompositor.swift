//
//  VideoCompositor.swift
//  VideoProcessingTwo
//
//  Created by Claude Code on 2025-11-04.
//

import AVFoundation
import Foundation

/// VideoCompositor manages the creation of AVMutableComposition instances from VideoProcessingTwo scenes.
/// It handles:
/// - Creating AVMutableVideoTracks for each VideoSource in the scene
/// - Falling back to the bundled black_video.mov if no video sources are present
/// - Looping the fallback video to match the scene duration
/// - Mapping source track IDs to VideoScene objects for custom compositing callbacks
public class VideoCompositor {
    private let scene: VideoScene
    private var videoSources: [VideoSource] = []

    /// Maps CMPersistentTrackID to VideoScene for retrieval in custom compositing callbacks
    public private(set) var sourceTrackIdToScene: [CMPersistentTrackID: VideoScene] = [:]

    /// Initialize with a VideoScene
    /// - Parameter scene: The VideoScene to build a composition from
    public init(scene: VideoScene) {
        self.scene = scene
        self.extractVideoSources(from: scene.group)
    }

    /// Build an AVMutableComposition from the scene
    /// - Returns: AVMutableComposition with video tracks for all video sources or fallback video
    /// - Throws: Error if bundle resource loading fails or asset operations fail
    public func buildComposition() throws -> AVMutableComposition {
        let composition = AVMutableComposition()

        if videoSources.isEmpty {
            // No video sources found, use black_video fallback
            try addBlackVideoLoop(to: composition)
        } else {
            // Add video tracks for each video source
            try addVideoSourceTracks(to: composition)
        }

        return composition
    }

    // MARK: - Private Methods

    /// Recursively extract all VideoSource instances from a Group hierarchy
    private func extractVideoSources(from group: Group) {
        // Extract from layers
        for layer in group.layers {
            for surface in layer.surfaces {
                if let videoSource = surface.source as? VideoSource {
                    videoSources.append(videoSource)
                }
            }
        }

        // Recursively extract from nested groups
        for nestedGroup in group.groups {
            extractVideoSources(from: nestedGroup)
        }
    }

    /// Add video tracks to composition for each discovered VideoSource
    private func addVideoSourceTracks(to composition: AVMutableComposition) throws {
        let targetDuration = CMTime(seconds: scene.duration, preferredTimescale: 600)

        for videoSource in videoSources {
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)
            ) else {
                throw AVVideoCompositionError.failedToCreateVideoTrack
            }

            let asset = AVURLAsset(url: videoSource.url)

            // Get the video track from the source asset
            guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
                throw AVVideoCompositionError.noVideoTracksInAsset
            }

            let videoDuration = sourceVideoTrack.timeRange.duration

            do {
                // If video is shorter than target duration, loop it to fill the duration
                var currentTime = CMTime.zero
                while currentTime.seconds < targetDuration.seconds {
                    let remainingTime = targetDuration.seconds - currentTime.seconds
                    let segmentDuration = min(videoDuration.seconds, remainingTime)
                    let videoTimeRange = CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: segmentDuration, preferredTimescale: 600)
                    )

                    try videoTrack.insertTimeRange(
                        videoTimeRange,
                        of: sourceVideoTrack,
                        at: currentTime
                    )

                    currentTime = CMTimeAdd(currentTime, videoTimeRange.duration)
                }

                // Set the trackID on the VideoSource so it knows which frame to pull from the render context
                videoSource.trackID = videoTrack.trackID

                // Store the mapping from this track's ID to the scene
                sourceTrackIdToScene[videoTrack.trackID] = scene
            } catch {
                throw AVVideoCompositionError.failedToInsertTimeRange(error)
            }
        }
    }

    /// Load the black_video.mov resource and create a looped composition for the scene duration
    private func addBlackVideoLoop(to composition: AVMutableComposition) throws {
        // Load black_video.mov from bundle
        guard let blackVideoURL = Bundle.module.url(forResource: "black_video", withExtension: "mov") else {
            throw AVVideoCompositionError.blackVideoResourceNotFound
        }

        let blackVideoAsset = AVURLAsset(url: blackVideoURL)

        // Get video track information
        guard let sourceVideoTrack = blackVideoAsset.tracks(withMediaType: .video).first else {
            throw AVVideoCompositionError.noVideoTracksInAsset
        }

        // Create a mutable video track in composition
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)
        ) else {
            throw AVVideoCompositionError.failedToCreateVideoTrack
        }

        let blackVideoDuration = sourceVideoTrack.timeRange.duration
        let sceneDuration = CMTime(seconds: scene.duration, preferredTimescale: CMTimeScale(scene.frameRate))

        var currentTime = CMTime.zero

        // Loop the black video until we reach the scene duration
        while currentTime.seconds < sceneDuration.seconds {
            let remainingTime = CMTimeSubtract(sceneDuration, currentTime)
            let insertDuration = remainingTime.seconds < blackVideoDuration.seconds ? remainingTime : blackVideoDuration

            let timeRangeToInsert = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: insertDuration.seconds, preferredTimescale: CMTimeScale(scene.frameRate))
            )

            do {
                try videoTrack.insertTimeRange(
                    timeRangeToInsert,
                    of: sourceVideoTrack,
                    at: currentTime
                )

                currentTime = CMTimeAdd(currentTime, timeRangeToInsert.duration)
            } catch {
                throw AVVideoCompositionError.failedToInsertTimeRange(error)
            }
        }

        // Store the mapping from this track's ID to the scene
        sourceTrackIdToScene[videoTrack.trackID] = scene
    }
}

// MARK: - Error Handling

/// Errors that can occur during AVVideoCompositing operations
public enum AVVideoCompositionError: LocalizedError {
    case blackVideoResourceNotFound
    case noVideoTracksInAsset
    case failedToCreateVideoTrack
    case failedToInsertTimeRange(Error)

    public var errorDescription: String? {
        switch self {
        case .blackVideoResourceNotFound:
            return "Failed to locate black_video.mov in bundle resources"
        case .noVideoTracksInAsset:
            return "No video tracks found in the asset"
        case .failedToCreateVideoTrack:
            return "Failed to create a mutable video track in composition"
        case .failedToInsertTimeRange(let error):
            return "Failed to insert time range into track: \(error.localizedDescription)"
        }
    }
}
