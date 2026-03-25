import Foundation
import CoreGraphics
import CoreMedia

public enum BodyPoseMetric {
    case jointX(String)
    case jointY(String)
    case jointDistance(String, String)
    case jointAngle(center: String, pointA: String, pointB: String)
    case averageConfidence([String])
}

#if canImport(Vision)
import Vision

public extension BodyPoseMetric {
    static func jointX(_ joint: VNHumanBodyPoseObservation.JointName) -> BodyPoseMetric {
        .jointX(joint.rawValue.rawValue)
    }

    static func jointY(_ joint: VNHumanBodyPoseObservation.JointName) -> BodyPoseMetric {
        .jointY(joint.rawValue.rawValue)
    }

    static func jointDistance(
        _ jointA: VNHumanBodyPoseObservation.JointName,
        _ jointB: VNHumanBodyPoseObservation.JointName
    ) -> BodyPoseMetric {
        .jointDistance(jointA.rawValue.rawValue, jointB.rawValue.rawValue)
    }

    static func jointAngle(
        center: VNHumanBodyPoseObservation.JointName,
        pointA: VNHumanBodyPoseObservation.JointName,
        pointB: VNHumanBodyPoseObservation.JointName
    ) -> BodyPoseMetric {
        .jointAngle(
            center: center.rawValue.rawValue,
            pointA: pointA.rawValue.rawValue,
            pointB: pointB.rawValue.rawValue
        )
    }
}
#endif

public enum BodyPosePersonSelection {
    case mostConfident
    case index(Int)
}

public struct BodyPoseFilterBinding {
    public var metric: BodyPoseMetric
    public var filterProperty: FilterProperty
    public var inputRange: ClosedRange<Double>
    public var outputRange: ClosedRange<Double>
    public var defaultValue: Double?
    /// 1.0 = no smoothing, 0.2 = heavily smoothed.
    public var smoothingFactor: Double
    public var clampOutput: Bool

    public init(
        metric: BodyPoseMetric,
        filterProperty: FilterProperty,
        inputRange: ClosedRange<Double> = 0.0...1.0,
        outputRange: ClosedRange<Double> = 0.0...1.0,
        defaultValue: Double? = nil,
        smoothingFactor: Double = 1.0,
        clampOutput: Bool = true
    ) {
        self.metric = metric
        self.filterProperty = filterProperty
        self.inputRange = inputRange
        self.outputRange = outputRange
        self.defaultValue = defaultValue
        self.smoothingFactor = smoothingFactor
        self.clampOutput = clampOutput
    }
}

/// Applies body pose metrics to filter properties at render-time.
public class BodyPoseFilterParameterDriver {
    public var timeline: BodyPoseTimeline
    public var personSelection: BodyPosePersonSelection

    private var bindingsByFilter: [ObjectIdentifier: [BodyPoseFilterBinding]] = [:]
    private var smoothedValuesByFilter: [ObjectIdentifier: [FilterProperty: Double]] = [:]

    public init(
        timeline: BodyPoseTimeline,
        personSelection: BodyPosePersonSelection = .mostConfident
    ) {
        self.timeline = timeline
        self.personSelection = personSelection
    }

    public func setBindings(_ bindings: [BodyPoseFilterBinding], for filter: any Filter) {
        let key = filterIdentity(for: filter)
        bindingsByFilter[key] = bindings
    }

    public func addBinding(_ binding: BodyPoseFilterBinding, for filter: any Filter) {
        let key = filterIdentity(for: filter)
        bindingsByFilter[key, default: []].append(binding)
    }

    public func clearBindings(for filter: any Filter) {
        let key = filterIdentity(for: filter)
        bindingsByFilter[key] = nil
        smoothedValuesByFilter[key] = nil
    }

    public func apply(to filter: any Filter, at time: CMTime) {
        let key = filterIdentity(for: filter)
        guard let bindings = bindingsByFilter[key], !bindings.isEmpty else {
            return
        }

        let frame = timeline.nearestFrame(to: time)
        let person = selectedPerson(from: frame)

        for binding in bindings {
            let metricValue = metric(binding.metric, for: person)
            guard let mappedValue = mappedValue(
                from: metricValue ?? binding.defaultValue,
                binding: binding
            ) else {
                continue
            }

            let smoothedValue = smooth(
                value: mappedValue,
                filterKey: key,
                property: binding.filterProperty,
                smoothingFactor: binding.smoothingFactor
            )

            filter.updateFilterValue(filterProperty: binding.filterProperty, value: smoothedValue)
        }
    }

    private func selectedPerson(from frame: BodyPoseFrame?) -> BodyPosePerson? {
        guard let people = frame?.people, !people.isEmpty else {
            return nil
        }

        switch personSelection {
        case .index(let index):
            guard people.indices.contains(index) else { return nil }
            return people[index]
        case .mostConfident:
            return people.max { lhs, rhs in
                averageConfidence(for: lhs) < averageConfidence(for: rhs)
            }
        }
    }

    private func averageConfidence(for person: BodyPosePerson) -> Double {
        guard !person.jointsByName.isEmpty else { return 0.0 }
        let sum = person.jointsByName.values.reduce(0.0) { partial, joint in
            partial + Double(joint.confidence)
        }
        return sum / Double(person.jointsByName.count)
    }

    private func metric(_ metric: BodyPoseMetric, for person: BodyPosePerson?) -> Double? {
        guard let person else { return nil }

        switch metric {
        case .jointX(let joint):
            return Double(person[joint]?.normalizedLocation.x ?? 0.0)
        case .jointY(let joint):
            return Double(person[joint]?.normalizedLocation.y ?? 0.0)
        case .jointDistance(let jointA, let jointB):
            guard let pointA = person[jointA]?.normalizedLocation,
                  let pointB = person[jointB]?.normalizedLocation else {
                return nil
            }
            return Double(hypot(pointA.x - pointB.x, pointA.y - pointB.y))
        case .jointAngle(let center, let pointA, let pointB):
            guard let centerPoint = person[center]?.normalizedLocation,
                  let a = person[pointA]?.normalizedLocation,
                  let b = person[pointB]?.normalizedLocation else {
                return nil
            }
            let v1 = CGVector(dx: a.x - centerPoint.x, dy: a.y - centerPoint.y)
            let v2 = CGVector(dx: b.x - centerPoint.x, dy: b.y - centerPoint.y)
            let magnitude = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
            guard magnitude > 0 else { return nil }

            let dot = (v1.dx * v2.dx) + (v1.dy * v2.dy)
            let normalizedDot = max(-1.0, min(1.0, dot / magnitude))
            return Double(acos(normalizedDot))
        case .averageConfidence(let joints):
            let confidences = joints.compactMap { person[$0] }.map { Double($0.confidence) }
            guard !confidences.isEmpty else { return nil }
            let sum = confidences.reduce(0.0, +)
            return sum / Double(confidences.count)
        }
    }

    private func mappedValue(from rawValue: Double?, binding: BodyPoseFilterBinding) -> Double? {
        guard let rawValue else { return nil }

        let inLower = binding.inputRange.lowerBound
        let inUpper = binding.inputRange.upperBound
        let outLower = binding.outputRange.lowerBound
        let outUpper = binding.outputRange.upperBound

        guard inUpper != inLower else {
            return outLower
        }

        var t = (rawValue - inLower) / (inUpper - inLower)
        if binding.clampOutput {
            t = max(0.0, min(1.0, t))
        }

        return outLower + (t * (outUpper - outLower))
    }

    private func smooth(
        value: Double,
        filterKey: ObjectIdentifier,
        property: FilterProperty,
        smoothingFactor: Double
    ) -> Double {
        let clampedSmoothing = max(0.0, min(1.0, smoothingFactor))
        var values = smoothedValuesByFilter[filterKey, default: [:]]

        let smoothed: Double
        if let previous = values[property] {
            smoothed = previous + ((value - previous) * clampedSmoothing)
        } else {
            smoothed = value
        }

        values[property] = smoothed
        smoothedValuesByFilter[filterKey] = values
        return smoothed
    }

    private func filterIdentity(for filter: any Filter) -> ObjectIdentifier {
        ObjectIdentifier(filter as AnyObject)
    }
}
