import Foundation

enum DayPhase: String {
    case day = "DAY"
    case sunset = "SUNSET"
    case night = "NIGHT"
    case morning = "MORNING"
}

struct DaylightState {
    let daylight: Float
    let warmth: Float
    let sunElevation: Float
    let phase: DayPhase
    let normalizedTime: Double
    var nightLights: Float { 1 - DayCycle.smoothstep(0.15, 0.85, daylight) }
    var isNight: Bool { daylight < 0.35 }
}

/// A complete solar cycle takes two minutes of active play, starting at midday.
/// Sampling is independent of frame rate; pausing the simulation also pauses the sun.
enum DayCycle {
    static let duration: Double = 120

    static func sample(elapsed: Double, offset: Double = 0) -> DaylightState {
        let time = (elapsed + offset).isFinite ? elapsed + offset : 0
        let wrapped = time.truncatingRemainder(dividingBy: duration)
        let phase = (wrapped < 0 ? wrapped + duration : wrapped) / duration
        let elevation = Float(cos(phase * 2 * .pi))
        let daylight = smoothstep(-0.16, 0.28, elevation)
        let warmth = max(0, 1 - abs(elevation - 0.05) / 0.4)
        let label: DayPhase = daylight < 0.1 ? .night : daylight > 0.9 ? .day : phase < 0.5 ? .sunset : .morning
        return DaylightState(daylight: daylight, warmth: warmth, sunElevation: elevation,
                             phase: label, normalizedTime: phase)
    }

    static func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }
}
