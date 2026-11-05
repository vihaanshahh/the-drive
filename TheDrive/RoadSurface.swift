import Foundation

/// The physical surface shared by mesh generation, wheel contacts and the chase camera.
/// `distance` increases along the road (world -Z); x increases toward the right shoulder.
enum RoadSurface {
    static let wheelbase: Float = 2.4
    static let trackWidth: Float = 1.8

    /// Continuous seeded height in meters. All longitudinal math stays in Double, even far from spawn.
    static func height(distance: Double, x: Float, seed: UInt64) -> Float {
        guard distance.isFinite, x.isFinite else { return 0 }
        let lateral = Double(min(5.7, max(-5.7, x)))
        let hills = broadHeight(distance: distance, seed: seed)
        let bank = (0.018 * wave(distance, wavelength: 89, seed: seed, salt: 11)
                    + 0.009 * noise(distance / 57, seed: seed, salt: 12)) * lateral
        let bumps = 0.065 * noise(distance / 8 + lateral * 0.22, seed: seed, salt: 21)
                    + 0.028 * noise(distance / 3 - lateral * 0.37, seed: seed, salt: 22)
        return Float(hills + bank + bumps + potholes(distance: distance, x: lateral, seed: seed))
    }

    /// Fits the body plane to four contact patches, rather than vibrating it at the center point.
    /// Positive pitch raises the nose along -Z; positive roll raises the right wheels along +X.
    static func sample(distance: Double, x: Float, seed: UInt64) -> RoadSample {
        guard distance.isFinite, x.isFinite else { return .flat }
        let halfLength = Double(wheelbase / 2)
        let halfWidth = trackWidth / 2
        let frontLeft = height(distance: distance + halfLength, x: x - halfWidth, seed: seed)
        let frontRight = height(distance: distance + halfLength, x: x + halfWidth, seed: seed)
        let rearLeft = height(distance: distance - halfLength, x: x - halfWidth, seed: seed)
        let rearRight = height(distance: distance - halfLength, x: x + halfWidth, seed: seed)
        let front = (frontLeft + frontRight) / 2
        let rear = (rearLeft + rearRight) / 2
        let left = (frontLeft + rearLeft) / 2
        let right = (frontRight + rearRight) / 2
        let mean = (front + rear) / 2
        let unevenness = abs(frontLeft + rearRight - frontRight - rearLeft) / 4
        let shortBump = abs(mean - Float(broadHeight(distance: distance, seed: seed)))
        return RoadSample(height: mean,
                          pitch: atan2(front - rear, wheelbase),
                          roll: atan2(right - left, trackWidth),
                          roughness: min(1, unevenness * 7 + shortBump * 3))
    }

    private static func broadHeight(distance: Double, seed: UInt64) -> Double {
        0.34 * wave(distance, wavelength: 113, seed: seed, salt: 1)
        + 0.19 * wave(distance, wavelength: 83, seed: seed, salt: 2)
        + 0.08 * noise(distance / 132, seed: seed, salt: 3)
    }

    private static func wave(_ distance: Double, wavelength: Double, seed: UInt64, salt: UInt64) -> Double {
        let phase = unitHash(0, seed: seed, salt: salt) * 2 * Double.pi
        let cycles = (distance / wavelength).truncatingRemainder(dividingBy: 1)
        return sin(cycles * 2 * Double.pi + phase)
    }

    /// Quintic interpolation gives adjacent lattice cells matching height, slope and curvature.
    private static func noise(_ coordinate: Double, seed: UInt64, salt: UInt64) -> Double {
        let bounded = abs(coordinate) < 9e18 ? coordinate : coordinate.truncatingRemainder(dividingBy: 1_073_741_824)
        let base = floor(bounded)
        let fraction = bounded - base
        let blend = fraction * fraction * fraction * (fraction * (fraction * 6 - 15) + 10)
        let first = unitHash(Int64(base), seed: seed, salt: salt)
        let second = unitHash(Int64(base) + 1, seed: seed, salt: salt)
        return (first + (second - first) * blend) * 2 - 1
    }

    /// Sparse compact depressions. Neighboring cells are sampled so cell boundaries never pop.
    private static func potholes(distance: Double, x: Double, seed: UInt64) -> Double {
        let rawCoordinate = distance / 17
        let coordinate = abs(rawCoordinate) < 9e18 ? rawCoordinate : rawCoordinate.truncatingRemainder(dividingBy: 1_073_741_824)
        let cell = Int64(floor(coordinate))
        let local = (coordinate - Double(cell)) * 17
        var depression = 0.0
        for offset in -1...1 {
            let index = cell + Int64(offset)
            guard unitHash(index, seed: seed, salt: 31) > 0.38 else { continue }
            let centerZ = unitHash(index, seed: seed, salt: 32) * 17 + Double(offset) * 17
            let centerX = (unitHash(index, seed: seed, salt: 33) * 2 - 1) * 4.3
            let length = 0.8 + unitHash(index, seed: seed, salt: 34) * 0.8
            let width = 0.65 + unitHash(index, seed: seed, salt: 35) * 0.55
            let dz = (local - centerZ) / length
            let dx = (x - centerX) / width
            let radiusSquared = dx * dx + dz * dz
            guard radiusSquared < 1 else { continue }
            let envelope = 1 - radiusSquared
            let depth = 0.07 + unitHash(index, seed: seed, salt: 36) * 0.09
            depression -= depth * envelope * envelope * envelope
        }
        return max(-0.16, depression)
    }

    private static func unitHash(_ index: Int64, seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ (UInt64(bitPattern: index) &* 0x9E3779B97F4A7C15) ^ (salt &* 0xD1B54A32D192ED03)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}

struct RoadSample {
    var height: Float
    var pitch: Float
    var roll: Float
    var roughness: Float

    static let flat = RoadSample(height: 0, pitch: 0, roll: 0, roughness: 0)
}

/// Suspension filters visual body motion; wheels can still use the unfiltered surface contacts.
struct RoadSuspension {
    private(set) var state: RoadSample = .flat
    private var initialized = false

    mutating func reset(to sample: RoadSample = .flat) {
        state = sample
        initialized = true
    }

    mutating func update(_ sample: RoadSample, dt: Float) -> RoadSample {
        guard initialized else { reset(to: sample); return state }
        guard dt.isFinite, dt > 0 else { return state }
        let step = min(dt, 0.1)
        let heightBlend = 1 - exp(-step * 22)
        let angleBlend = 1 - exp(-step * 12)
        let roughnessBlend = 1 - exp(-step * 9)
        state.height += (sample.height - state.height) * heightBlend
        state.pitch += (sample.pitch - state.pitch) * angleBlend
        state.roll += (sample.roll - state.roll) * angleBlend
        state.roughness += (sample.roughness - state.roughness) * roughnessBlend
        return state
    }
}
