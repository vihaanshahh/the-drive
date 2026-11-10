import XCTest
import SceneKit
@testable import TheDrive

@MainActor
final class PaceTests: XCTestCase {
    func testBaselineRisesWithDistanceAndKeepsTheFirstSecondsFamiliar() {
        XCTAssertEqual(DrivingPace.baseline(distance: 0), 72)
        XCTAssertLessThan(DrivingPace.baseline(distance: 120), 73)
        XCTAssertEqual(DrivingPace.baseline(distance: 1_000), 105)
        XCTAssertEqual(DrivingPace.baseline(distance: 3_000), 125)
        XCTAssertEqual(DrivingPace.baseline(distance: 6_000), 145)
        XCTAssertEqual(DrivingPace.baseline(distance: 1e12), 145)
        var previous = 72.0
        for distance in stride(from: 0.0, through: 12_000, by: 5) {
            let baseline = DrivingPace.baseline(distance: distance)
            XCTAssertGreaterThanOrEqual(baseline, previous)
            previous = baseline
        }
    }

    func testSeededDipsAreBriefSmoothAndLeaveMostOfTheRouteFast() {
        var fullPace = 0
        var total = 0
        var samples: [Double] = []
        var alternate: [Double] = []
        var previous: Double?
        for distance in stride(from: 0.0, through: 24_000, by: 2) {
            let sample = DrivingPace.sample(distance: distance, seed: 17)
            XCTAssertEqual(sample, DrivingPace.sample(distance: distance, seed: 17))
            XCTAssertGreaterThanOrEqual(sample.targetKPH, sample.baselineKPH * 0.75)
            XCTAssertLessThanOrEqual(sample.targetKPH, sample.baselineKPH)
            XCTAssertTrue(sample.targetKPH.isFinite)
            if let previous {
                XCTAssertLessThan(abs(sample.targetKPH - previous), 2,
                                  "Seeded windows must ease into and out of a slowdown.")
            }
            previous = sample.targetKPH
            if sample.slowdownFraction == 0 { fullPace += 1 }
            samples.append(sample.targetKPH)
            alternate.append(DrivingPace.sample(distance: distance, seed: 18).targetKPH)
            total += 1
        }
        let fastFraction = Double(fullPace) / Double(total)
        XCTAssertGreaterThan(fastFraction, 0.82)
        XCTAssertLessThan(fastFraction, 0.91)
        XCTAssertNotEqual(samples, alternate, "Another route should place its short breathers differently.")
    }

    func testVelocityFilteringIsBoundedAndDoesNotDependOnDisplayFrameRate() {
        let dt = 1.0 / 60
        let accelerating = DrivingPace.filteredVelocity(current: 20, target: 40, dt: dt)
        let easing = DrivingPace.filteredVelocity(current: 40, target: 30, dt: dt)
        XCTAssertLessThanOrEqual(accelerating - 20, 2.4 * dt + 0.000001)
        XCTAssertLessThanOrEqual(40 - easing, 4.5 * dt + 0.000001)
        XCTAssertEqual(DrivingPace.filteredVelocity(current: 28, target: 40, dt: 0), 28)

        func simulate(fps: Double) -> (distance: Double, velocity: Double) {
            var distance = 0.0
            var velocity = 20.0
            for _ in 0..<Int(120 * fps) {
                let target = DrivingPace.sample(distance: distance, seed: 17).targetKPH / 3.6
                velocity = DrivingPace.filteredVelocity(current: velocity, target: target, dt: 1 / fps)
                distance += velocity / fps
            }
            return (distance, velocity)
        }
        let thirty = simulate(fps: 30)
        let oneTwenty = simulate(fps: 120)
        XCTAssertEqual(thirty.distance, oneTwenty.distance, accuracy: 2)
        XCTAssertEqual(thirty.velocity, oneTwenty.velocity, accuracy: 0.1)
    }

    func testHighSpeedHazardsKeepReactionTimeAndStayInsideTheActiveRoad() {
        XCTAssertEqual(DrivingPace.hazardLead(velocity: 20), 130,
                       "The opening hazard timing should be unchanged.")
        for velocity in stride(from: 20.0, through: 157 / 3.6, by: 0.25) {
            let lead = DrivingPace.hazardLead(velocity: velocity)
            XCTAssertGreaterThanOrEqual(lead / velocity, 4.3)
            XCTAssertLessThanOrEqual(lead, 190)
            XCTAssertGreaterThanOrEqual(lead, 130)
        }
    }

    func testActualRunAcceleratesAndPauseAndRestartResetPaceCorrectly() throws {
        let game = GameModel(seed: 17)
        game.start()
        let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
        advanceSafely(game, world: world, from: 0, seconds: 25)
        XCTAssertFalse(game.isGameOver)
        XCTAssertGreaterThan(game.distance, 500, "Acceleration must move the world faster, not only the HUD.")
        XCTAssertGreaterThan(game.speed, 82)
        let speed = game.speed
        let distance = game.distance
        game.setPaused(true)
        advanceSafely(game, world: world, from: 25, seconds: 3)
        XCTAssertEqual(game.speed, speed)
        XCTAssertEqual(game.distance, distance)
        game.setPaused(false)
        game.update(time: 300)
        XCTAssertEqual(game.speed, speed)
        XCTAssertEqual(game.distance, distance)
        advanceSafely(game, world: world, from: 300, seconds: 0.5)
        XCTAssertLessThan(game.distance - distance, 15, "A resumed frame must not spend time from the pause.")
        game.restart()
        XCTAssertEqual(game.speed, 72)
        XCTAssertEqual(game.distance, 0)
    }

    func testOpeningDistanceDoesNotIncreaseGameplayDifficulty() throws {
        let cinematic = GameModel(seed: 17)
        advance(cinematic, from: 0, seconds: 5)
        cinematic.beginOpening()
        advance(cinematic, from: 5, seconds: 6)
        cinematic.skipOpening()
        let direct = GameModel(seed: 17)
        direct.start()
        XCTAssertEqual(cinematic.speed, 72)
        func frontRoad(in game: GameModel) throws -> SCNNode {
            let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
            return try XCTUnwrap(world.childNodes.filter {
                $0.childNode(withName: "road", recursively: false) != nil
            }.min { $0.position.z < $1.position.z })
        }
        let cinematicRoad = try frontRoad(in: cinematic)
        let directRoad = try frontRoad(in: direct)
        let cinematicBefore = cinematicRoad.position.z
        let directBefore = directRoad.position.z
        advance(cinematic, from: 11, seconds: 3)
        advance(direct, from: 0, seconds: 3)
        XCTAssertEqual(cinematic.simulationClock, direct.simulationClock, accuracy: 0.000000001)
        XCTAssertNotNil(cinematicRoad.parent)
        XCTAssertNotNil(directRoad.parent)
        XCTAssertEqual(cinematicRoad.position.z - cinematicBefore, directRoad.position.z - directBefore,
                       accuracy: 0.01, "The real road must cover the same distance regardless of the intro.")
        // Published HUD values update every 0.1s; absolute timestamp rounding can shift a refresh.
        XCTAssertEqual(cinematic.speed, direct.speed, accuracy: 0.02)
        XCTAssertEqual(Double(cinematic.distance), Double(direct.distance), accuracy: 2)
    }

    func testEngineBonusComposesWithBothFastSectionsAndEasings() {
        for distance in stride(from: 0.0, through: 12_000, by: 11) {
            let stock = DrivingPace.sample(distance: distance, seed: 17)
            let tuned = DrivingPace.sample(distance: distance, seed: 17, engineTier: 3)
            XCTAssertEqual(tuned.targetKPH - stock.targetKPH, 12, accuracy: 0.0001)
            XCTAssertEqual(tuned.slowdownFraction, stock.slowdownFraction)
        }
        let garage = GarageProgress(defaults: nil)
        garage.award(distanceCash: 300)
        for _ in 0..<3 { XCTAssertTrue(garage.purchase(.engine)) }
        let game = GameModel(seed: 17, garage: garage)
        game.start()
        XCTAssertEqual(game.speed, 84)
        advance(game, from: 0, seconds: 1.3)
        XCTAssertGreaterThan(game.distance, 27)
        game.restart()
        XCTAssertEqual(game.speed, 84)
    }

    /// Keep this speed test independent of combat deaths, while using the real road and movement.
    private func advanceSafely(_ game: GameModel, world: SCNNode, from start: Double, seconds: Double) {
        game.update(time: start)
        for frame in 1...max(1, Int((seconds * 60).rounded())) {
            for node in world.childNodes {
                if node.name == "pursuer" { node.position.z = 200 }
                if node.name == "roadHazard" || node.name == "pedestrianHazard" { node.position.x = 20 }
            }
            game.update(time: start + Double(frame) / 60)
        }
    }

    private func advance(_ game: GameModel, from start: Double, seconds: Double) {
        game.update(time: start)
        for frame in 1...max(1, Int((seconds * 60).rounded())) {
            game.update(time: start + Double(frame) / 60)
        }
    }
}
