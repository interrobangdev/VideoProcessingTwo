//
//  Filter.swift
//  VideoProcessingTwoContainer
//
//  Created by Jake Gundersen on 4/3/24.
//

import Foundation
import CoreMedia
import CoreImage

public enum FilterProperty: String {
    case radius
    case scale
    case rotation
    case translation
    case centerPoint
    case fade
    case brightness
    case contrast
    case saturation
    case intensity
}

public protocol Filter {
//    var filterConfig: FilterConfig { get set }
    var filterAnimators: [FilterAnimator] { get set }
    func updateFilterValue(filterProperty: FilterProperty, value: Any)
    func filterContent(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage?
}

// MARK: - Filter Extension with Default Implementation

public extension Filter {
    /// Default implementation that applies animator-driven updates before processing the image
    func filterContentWithAnimators(image: CIImage, sourceTime: CMTime?, sceneTime: CMTime?, compositionTime: CMTime?) -> CIImage? {
        // Get the current time for animation calculations
        let currentTime = compositionTime ?? sceneTime ?? sourceTime ?? CMTime.zero
        let timeSeconds = CMTimeGetSeconds(currentTime)

        // Apply all animators to update filter properties
        for animator in filterAnimators {
            let animatedValue = animator.tweenValue(time: timeSeconds)
            updateFilterValue(filterProperty: animator.animationProperty, value: animatedValue)
        }

        // Process the image with updated values
        return filterContent(image: image, sourceTime: sourceTime, sceneTime: sceneTime, compositionTime: compositionTime)
    }
}

public protocol TweenFunctionProvider {
    func tweenValue(input: Double) -> Double
}


//
//public protocol FilterAnimator {
//    var type: AnimationValueType { get set }
//    var startValue: Double? { get set }
//    var endValue: Double? { get set }
//    var startPoint: CGPoint? { get set }
//    var endPoint: CGPoint? { get set }
//    var startTime: Double { get set }
//    var endTime: Double { get set }
//    var animationFunction: AnimationFunctionProvider { get set }
//    
//    func animateValue(time: Double) -> Any
//}
