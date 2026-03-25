import CoreGraphics
import CoreImage
import CoreMedia
import Foundation

public class ShakeFilter: Filter {
    public var filterAnimators: [FilterAnimator]

    /// Normalized translation amplitude relative to image size.
    public var translationAmplitude: CGPoint
    /// Rotation amplitude in radians.
    public var rotationAmplitude: Double
    /// Scale amplitude around 1.0.
    public var scaleAmplitude: Double
    /// Base oscillation frequency in Hz.
    public var speed: Double

    public init(
        translationAmplitude: CGPoint = CGPoint(x: 0.02, y: 0.02),
        rotationAmplitude: Double = 0.04,
        scaleAmplitude: Double = 0.06,
        speedHz: Double = 5.5,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.translationAmplitude = translationAmplitude
        self.rotationAmplitude = rotationAmplitude
        self.scaleAmplitude = scaleAmplitude
        self.speed = speedHz
        self.filterAnimators = filterAnimators
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .rotation:
            if let value = value as? Double {
                rotationAmplitude = value
            }
        case .scale:
            if let value = value as? Double {
                scaleAmplitude = value
            }
        case .translation:
            if let value = value as? CGPoint {
                translationAmplitude = value
            }
        default:
            break
        }
    }

    public func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        let t = CMTimeGetSeconds(compositionTime ?? sceneTime ?? sourceTime ?? .zero)
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)

        let tx = translationAmplitude.x * extent.width * CGFloat(sin(2.0 * Double.pi * speed * t))
        let ty = translationAmplitude.y * extent.height * CGFloat(sin(2.0 * Double.pi * speed * 1.37 * t + 1.2))
        let rotation = rotationAmplitude * sin(2.0 * Double.pi * speed * 0.91 * t + 0.4)
        let scale = 1.0 + scaleAmplitude * sin(2.0 * Double.pi * speed * 0.73 * t + 2.0)

        let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
        let scaleTransform = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        let rotateTransform = CGAffineTransform(rotationAngle: CGFloat(rotation))
        let fromOrigin = CGAffineTransform(translationX: center.x, y: center.y)
        let translateTransform = CGAffineTransform(translationX: tx, y: ty)

        let transform = toOrigin
            .concatenating(scaleTransform)
            .concatenating(rotateTransform)
            .concatenating(fromOrigin)
            .concatenating(translateTransform)

        return image.transformed(by: transform).cropped(to: extent)
    }
}
