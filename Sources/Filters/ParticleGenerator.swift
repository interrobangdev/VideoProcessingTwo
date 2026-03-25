import Foundation
import simd

/// Generic provider of normalized particle positions for GPU algorithms.
/// Coordinates are expected in 0...1 space.
public protocol ParticleGenerator {
    func particlePositions(at time: Double, count: Int) -> [SIMD2<Float>]
}

/// Deterministic animated particle field that can be reused by any effect.
public final class AnimatedParticleGenerator: ParticleGenerator {
    public var seed: UInt64
    public var velocity: Float
    public var orbitAmplitude: Float
    public var orbitSpeed: Float
    public var jitterAmount: Float

    public init(
        seed: UInt64 = 0xC0FFEE,
        velocity: Float = 0.10,
        orbitAmplitude: Float = 0.07,
        orbitSpeed: Float = 0.45,
        jitterAmount: Float = 0.25
    ) {
        self.seed = seed
        self.velocity = velocity
        self.orbitAmplitude = orbitAmplitude
        self.orbitSpeed = orbitSpeed
        self.jitterAmount = jitterAmount
    }

    public func particlePositions(at time: Double, count: Int) -> [SIMD2<Float>] {
        let total = max(0, count)
        guard total > 0 else { return [] }

        let t = Float(time)
        var result: [SIMD2<Float>] = []
        result.reserveCapacity(total)

        for index in 0..<total {
            let i = UInt64(index)
            let base = SIMD2(
                random01(i &* 2 &+ 0x11),
                random01(i &* 2 &+ 0x71)
            )

            let velocityVector = SIMD2(
                (random01(i &* 3 &+ 0x211) - 0.5) * 2.0,
                (random01(i &* 3 &+ 0x2A1) - 0.5) * 2.0
            ) * velocity

            let phase = random01(i &+ 0x1001) * (Float.pi * 2.0)
            let orbitScale = orbitAmplitude * (0.35 + random01(i &+ 0x1177) * 0.65)
            let orbit = SIMD2(
                cos(t * orbitSpeed + phase),
                sin(t * (orbitSpeed * 1.17) + phase * 1.31)
            ) * orbitScale

            let jitter = SIMD2(
                sin((t + Float(index) * 0.17) * 6.7),
                cos((t + Float(index) * 0.11) * 5.3)
            ) * (jitterAmount * 0.02)

            let animated = base + velocityVector * t + orbit + jitter
            result.append(SIMD2(wrap01(animated.x), wrap01(animated.y)))
        }

        return result
    }

    private func random01(_ value: UInt64) -> Float {
        let hashed = hash(value ^ seed)
        let mantissa = UInt32(truncatingIfNeeded: hashed & 0x00FF_FFFF)
        return Float(mantissa) / Float(0x0100_0000)
    }

    private func hash(_ value: UInt64) -> UInt64 {
        var x = value &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    private func wrap01(_ value: Float) -> Float {
        let fractional = value - floor(value)
        return fractional < 0.0 ? fractional + 1.0 : fractional
    }
}
