import Foundation

/// Run distance drives difficulty; the route seed fixes where the brief easings occur.
enum DrivingPace {
    struct Sample: Equatable {
        let baselineKPH: Double
        let targetKPH: Double
        let slowdownFraction: Double
    }

    static func baseline(distance: Double) -> Double {
        let d = distance.isFinite ? max(0, distance) : 0
        // Preserve the opening seconds, then reach highway pace within the first kilometer.
        if d <= 120 { return 72 + d * 0.006 }
        if d < 1_000 { return interpolate(72.72, 105, progress: (d - 120) / 880) }
        if d < 3_000 { return interpolate(105, 125, progress: (d - 1_000) / 2_000) }
        if d < 6_000 { return interpolate(125, 145, progress: (d - 3_000) / 3_000) }
        return 145
    }

    static func sample(distance: Double, seed: UInt64, engineTier: Int = 0) -> Sample {
        let d = distance.isFinite ? max(0, distance) : 0
        let baselineKPH = baseline(distance: d)
        let blockLength = 1_200.0
        let block = (d / blockLength).rounded(.down)
        let center = 700 + unit(seed: seed, block: block, salt: 1) * 250
        let seconds = 3.6 + unit(seed: seed, block: block, salt: 2) * 0.8
        let centerPace = baseline(distance: block * blockLength + center)
        let span = max(110, centerPace / 3.6 * seconds)
        let phase = d.truncatingRemainder(dividingBy: blockLength)
        let pulseProgress = (phase - center + span / 2) / span
        var slowdown = 0.0
        if pulseProgress > 0 && pulseProgress < 1 {
            let pulse = sin(pulseProgress * .pi)
            slowdown = (0.15 + unit(seed: seed, block: block, salt: 3) * 0.10) * pulse * pulse
        }
        let engineBonus = Double(min(3, max(0, engineTier))) * 4
        return Sample(baselineKPH: baselineKPH,
                      targetKPH: baselineKPH * (1 - slowdown) + engineBonus,
                      slowdownFraction: slowdown)
    }

    /// Speeds are meters/second. Exponential response plus acceleration limits keeps cuts gentle.
    static func filteredVelocity(current: Double, target: Double, dt: Double) -> Double {
        guard dt.isFinite, dt > 0, target.isFinite, target >= 0 else { return current }
        guard current.isFinite else { return target }
        let response = (target - current) * (1 - exp(-dt / 0.45))
        let change = min(2.4 * dt, max(-4.5 * dt, response))
        return max(0, current + change)
    }

    /// Keep roughly 4–6 seconds of lead as speed rises; all hazards stay within the active road.
    static func hazardLead(velocity: Double) -> Double {
        let v = velocity.isFinite ? max(0, velocity) : 20
        return min(190, max(130, v * 4.8))
    }

    private static func interpolate(_ first: Double, _ second: Double, progress: Double) -> Double {
        let p = min(1, max(0, progress))
        return first + (second - first) * p * p * (3 - 2 * p)
    }

    private static func unit(seed: UInt64, block: Double, salt: UInt64) -> Double {
        var value = seed ^ (block.bitPattern &* 0x9E3779B97F4A7C15) ^ (salt &* 0xD1B54A32D192ED03)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64.max >> 11)
    }
}
