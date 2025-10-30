//
//  BezierTweenFunction.swift
//  VideoProcessingTwo
//
//  Multi-segment bezier path for complex animation curves
//

import Foundation
import CoreGraphics

/// A point on a bezier curve with optional control points
public struct BezierPoint {
    public let x: Double
    public let y: Double
    public let controlPoint1: CGPoint?  // Control point before this point
    public let controlPoint2: CGPoint?  // Control point after this point

    public init(x: Double, y: Double, controlPoint1: CGPoint? = nil, controlPoint2: CGPoint? = nil) {
        self.x = x
        self.y = y
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
    }

    /// Create a point with symmetric control handles
    public init(x: Double, y: Double, controlOffset: CGPoint) {
        self.x = x
        self.y = y
        self.controlPoint1 = CGPoint(x: x - controlOffset.x, y: y - controlOffset.y)
        self.controlPoint2 = CGPoint(x: x + controlOffset.x, y: y + controlOffset.y)
    }
}

/// Multi-segment bezier curve for complex animation easing
/// Allows you to define a path with multiple points and control handles
public class BezierPathTweenFunction: TweenFunctionProvider {
    private let points: [BezierPoint]
    private let segments: [BezierSegment]

    /// Create a bezier path from multiple points
    /// - Parameter points: Array of points defining the curve (must include at least 2 points)
    /// - Note: First point should have x=0, last point should have x=1 for proper animation timing
    public init(points: [BezierPoint]) {
        precondition(points.count >= 2, "Bezier path must have at least 2 points")
        self.points = points

        // Create segments between consecutive points
        var segments: [BezierSegment] = []
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]

            // Determine control points for this segment
            let cp1 = start.controlPoint2 ?? CGPoint(x: start.x, y: start.y)
            let cp2 = end.controlPoint1 ?? CGPoint(x: end.x, y: end.y)

            let segment = BezierSegment(
                start: CGPoint(x: start.x, y: start.y),
                control1: cp1,
                control2: cp2,
                end: CGPoint(x: end.x, y: end.y)
            )
            segments.append(segment)
        }
        self.segments = segments
    }

    public func tweenValue(input: Double) -> Double {
        let t = max(0, min(1, input))

        // Find which segment contains this x value
        guard let segment = findSegment(forX: t) else {
            // Fallback to linear if segment not found
            return t
        }

        // Solve for y value in that segment
        return segment.solveForY(x: t)
    }

    private func findSegment(forX x: Double) -> BezierSegment? {
        // Find the segment whose x range contains the input x
        for segment in segments {
            if x >= segment.start.x && x <= segment.end.x {
                return segment
            }
        }

        // If not found, return first or last segment
        if x < segments.first!.start.x {
            return segments.first
        } else {
            return segments.last
        }
    }
}

/// A single cubic bezier curve segment
private struct BezierSegment {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    /// Cubic bezier curve formula
    func pointAt(_ t: Double) -> CGPoint {
        let oneMinusT = 1.0 - t
        let x = oneMinusT * oneMinusT * oneMinusT * start.x +
                3.0 * oneMinusT * oneMinusT * t * control1.x +
                3.0 * oneMinusT * t * t * control2.x +
                t * t * t * end.x

        let y = oneMinusT * oneMinusT * oneMinusT * start.y +
                3.0 * oneMinusT * oneMinusT * t * control1.y +
                3.0 * oneMinusT * t * t * control2.y +
                t * t * t * end.y

        return CGPoint(x: x, y: y)
    }

    /// Derivative for Newton-Raphson
    func derivativeXAt(_ t: Double) -> Double {
        let oneMinusT = 1.0 - t
        return 3.0 * oneMinusT * oneMinusT * (control1.x - start.x) +
               6.0 * oneMinusT * t * (control2.x - control1.x) +
               3.0 * t * t * (end.x - control2.x)
    }

    /// Solve for y given x using Newton-Raphson
    func solveForY(x targetX: Double) -> Double {
        // Normalize x to segment's x range
        let xRange = end.x - start.x
        if abs(xRange) < 0.000001 {
            // Vertical segment, return average y
            return (start.y + end.y) / 2.0
        }

        let normalizedX = (targetX - start.x) / xRange
        var t = normalizedX  // Initial guess

        // Newton-Raphson iterations
        for _ in 0..<8 {
            let point = pointAt(t)
            let currentX = (point.x - start.x) / xRange
            let error = currentX - normalizedX

            if abs(error) < 0.000001 {
                return point.y
            }

            let derivative = derivativeXAt(t) / xRange
            if abs(derivative) < 0.000001 {
                break
            }

            t = t - error / derivative
            t = max(0, min(1, t))
        }

        return pointAt(t).y
    }
}

// MARK: - Preset Curves

extension BezierPathTweenFunction {
    /// Linear interpolation (straight line from 0,0 to 1,1)
    public static var linear: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0),
            BezierPoint(x: 1, y: 1)
        ])
    }

    /// Ease in out with smooth acceleration
    public static var easeInOut: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.42, y: 0)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.58, y: 1))
        ])
    }

    /// S-curve with overshoot in the middle
    public static var sCurveWithBump: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.2, y: 0)),
            BezierPoint(x: 0.5, y: 0.6, controlPoint1: CGPoint(x: 0.3, y: 0.8), controlPoint2: CGPoint(x: 0.7, y: 0.8)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.8, y: 1))
        ])
    }

    /// Three-step animation (pauses at 0.33 and 0.66)
    public static var threeStep: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.15, y: 0)),
            BezierPoint(x: 0.33, y: 0.33, controlPoint1: CGPoint(x: 0.28, y: 0.33), controlPoint2: CGPoint(x: 0.38, y: 0.33)),
            BezierPoint(x: 0.66, y: 0.66, controlPoint1: CGPoint(x: 0.61, y: 0.66), controlPoint2: CGPoint(x: 0.71, y: 0.66)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.85, y: 1))
        ])
    }

    /// Bounce effect with multiple bounces
    public static var multiBounce: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.1, y: 0)),
            BezierPoint(x: 0.25, y: 0.4, controlPoint1: CGPoint(x: 0.2, y: 0.5), controlPoint2: CGPoint(x: 0.3, y: 0.5)),
            BezierPoint(x: 0.5, y: 0.7, controlPoint1: CGPoint(x: 0.4, y: 0.9), controlPoint2: CGPoint(x: 0.6, y: 0.9)),
            BezierPoint(x: 0.75, y: 0.9, controlPoint1: CGPoint(x: 0.7, y: 1.05), controlPoint2: CGPoint(x: 0.8, y: 1.05)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.9, y: 1.1))
        ])
    }

    /// Wave pattern
    public static var wave: BezierPathTweenFunction {
        BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: 0.1, y: 0.3)),
            BezierPoint(x: 0.25, y: 0.5, controlPoint1: CGPoint(x: 0.2, y: 0.7), controlPoint2: CGPoint(x: 0.3, y: 0.3)),
            BezierPoint(x: 0.5, y: 0.5, controlPoint1: CGPoint(x: 0.45, y: 0.7), controlPoint2: CGPoint(x: 0.55, y: 0.3)),
            BezierPoint(x: 0.75, y: 0.5, controlPoint1: CGPoint(x: 0.7, y: 0.7), controlPoint2: CGPoint(x: 0.8, y: 0.3)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: 0.9, y: 0.7))
        ])
    }

    /// Custom builder for creating your own curves
    public static func custom(_ points: [BezierPoint]) -> BezierPathTweenFunction {
        BezierPathTweenFunction(points: points)
    }
}

// MARK: - Simple Cubic Bezier (for backwards compatibility)

/// Single cubic bezier curve (like CSS cubic-bezier)
public class CubicBezierTweenFunction: TweenFunctionProvider {
    private let pathFunction: BezierPathTweenFunction

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.pathFunction = BezierPathTweenFunction(points: [
            BezierPoint(x: 0, y: 0, controlPoint2: CGPoint(x: x1, y: y1)),
            BezierPoint(x: 1, y: 1, controlPoint1: CGPoint(x: x2, y: y2))
        ])
    }

    public func tweenValue(input: Double) -> Double {
        return pathFunction.tweenValue(input: input)
    }
}

// MARK: - Preset CSS-style curves

extension CubicBezierTweenFunction {
    public static var ease: CubicBezierTweenFunction {
        CubicBezierTweenFunction(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    }

    public static var easeIn: CubicBezierTweenFunction {
        CubicBezierTweenFunction(x1: 0.42, y1: 0.0, x2: 1.0, y2: 1.0)
    }

    public static var easeOut: CubicBezierTweenFunction {
        CubicBezierTweenFunction(x1: 0.0, y1: 0.0, x2: 0.58, y2: 1.0)
    }

    public static var easeInOut: CubicBezierTweenFunction {
        CubicBezierTweenFunction(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0)
    }
}
