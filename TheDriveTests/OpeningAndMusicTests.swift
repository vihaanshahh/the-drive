import XCTest
import SceneKit
import AVFoundation
import Combine
@testable import TheDrive

@MainActor
final class OpeningAndMusicTests: XCTestCase {
    func testLiveSoundtrackStartsPausesResumesMutesAndStops() async {
        let soundtrack = Soundtrack()
        var subscriptions = Set<AnyCancellable>()
        defer {
            soundtrack.stop()
            subscriptions.removeAll()
        }
        XCTAssertTrue(soundtrack.isAvailable, "The live controller must find both bundled songs.")
        let started = expectation(description: "AVAudioEngine starts the seeded soundtrack")
        soundtrack.$isPlaying.filter { $0 }.first()
            .sink { _ in started.fulfill() }.store(in: &subscriptions)
        let noPlaybackFailure = expectation(description: "Playback stays available through transport changes")
        noPlaybackFailure.isInverted = true
        soundtrack.$status.filter { $0 == "Music unavailable" }
            .sink { _ in noPlaybackFailure.fulfill() }.store(in: &subscriptions)

        soundtrack.start(seed: 17)
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(soundtrack.isPlaying, "Readiness must follow actual graph startup.")
        XCTAssertEqual(soundtrack.status, "Seeded bar mix")
        soundtrack.setPaused(true)
        XCTAssertFalse(soundtrack.isPlaying)

        let resumed = expectation(description: "Soundtrack resumes")
        soundtrack.$isPlaying.filter { $0 }.first()
            .sink { _ in resumed.fulfill() }.store(in: &subscriptions)
        soundtrack.setPaused(false)
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertTrue(soundtrack.isPlaying)
        soundtrack.setMuted(true)
        XCTAssertTrue(soundtrack.isMuted)
        XCTAssertTrue(soundtrack.isPlaying, "Muting should keep the seeded sequence running.")
        soundtrack.setMuted(false)
        XCTAssertFalse(soundtrack.isMuted)
        XCTAssertTrue(soundtrack.isPlaying)
        // Resume runs on the audio worker; give an asynchronous graph error time to surface.
        await fulfillment(of: [noPlaybackFailure], timeout: 0.25)
        soundtrack.stop()
        XCTAssertFalse(soundtrack.isPlaying)
        XCTAssertEqual(soundtrack.status, "Music ready")
    }

    func testMusicPlanRepeatsForItsSeedAndVariesForAnotherRoute() throws {
        let tracks = musicFixtures
        var first = SoundtrackPlanner(seed: 17, tracks: tracks)
        var replay = SoundtrackPlanner(seed: 17, tracks: tracks)
        var other = SoundtrackPlanner(seed: 18, tracks: tracks)
        var firstChoices: [String] = []
        var otherChoices: [String] = []
        for _ in 0..<64 {
            let piece = try XCTUnwrap(first.next())
            let repeated = try XCTUnwrap(replay.next())
            let different = try XCTUnwrap(other.next())
            XCTAssertEqual(musicSignature(piece), musicSignature(repeated))
            firstChoices.append(musicSignature(piece))
            otherChoices.append(musicSignature(different))
        }
        XCTAssertNotEqual(firstChoices, otherChoices,
                          "Changing the route seed must change the remix, independently of frame timing.")
    }

    func testMusicPlanUsesWholeBarsAndNeverLeavesGapsOrReadsPastATrack() throws {
        let tracks = musicFixtures
        var planner = SoundtrackPlanner(seed: 0xBA2AA2, tracks: tracks)
        let sampleRate = Double(SoundtrackPlanner.sampleRate)
        let tailFrames = Int64((sampleRate * SoundtrackCrossfade.duration).rounded())
        var timelineEnd: Int64 = 0
        var recent: [Int] = []
        var lastChoice = ""
        for _ in 0..<512 {
            let piece = try XCTUnwrap(planner.next())
            XCTAssertTrue(tracks.indices.contains(piece.trackIndex))
            let track = tracks[piece.trackIndex]
            XCTAssertTrue([1, 2, 4, 8].contains(piece.barCount))
            XCTAssertGreaterThanOrEqual(piece.startBar, 0)
            XCTAssertEqual(piece.timelineStartFrame, timelineEnd,
                           "Every piece must start exactly where the preceding output ends.")
            XCTAssertEqual(Double(piece.frameCount), Double(piece.barCount) * track.framesPerBar, accuracy: 1)
            let expectedSource = track.firstDownbeat * sampleRate + Double(piece.startBar) * track.framesPerBar
            XCTAssertEqual(Double(piece.sourceStartFrame), expectedSource, accuracy: 1)
            XCTAssertGreaterThanOrEqual(piece.sourceStartFrame, 0)
            XCTAssertLessThanOrEqual(piece.sourceStartFrame + Int64(piece.frameCount) + tailFrames,
                                     Int64((track.duration * sampleRate).rounded(.down)),
                                     "The crossfade tail must also be inside the audio file.")
            timelineEnd += Int64(piece.frameCount)
            recent.append(piece.trackIndex)
            if recent.count > 3 { recent.removeFirst() }
            if recent.count == 3 {
                XCTAssertGreaterThan(Set(recent).count, 1, "The mix should keep cutting between both songs.")
            }
            let choice = "\(piece.trackIndex):\(piece.startBar):\(piece.barCount)"
            XCTAssertNotEqual(choice, lastChoice, "Consecutive cuts should not repeat the identical section.")
            lastChoice = choice
        }
    }

    func testMusicCrossfadeKeepsEqualPowerAtEveryPoint() {
        let beginning = SoundtrackCrossfade.gains(progress: 0)
        let ending = SoundtrackCrossfade.gains(progress: 1)
        XCTAssertEqual(beginning.outgoing, 1, accuracy: 0.0001)
        XCTAssertEqual(beginning.incoming, 0, accuracy: 0.0001)
        XCTAssertEqual(ending.outgoing, 0, accuracy: 0.0001)
        XCTAssertEqual(ending.incoming, 1, accuracy: 0.0001)
        for step in 0...100 {
            let gains = SoundtrackCrossfade.gains(progress: Float(step) / 100)
            XCTAssertEqual(gains.outgoing * gains.outgoing + gains.incoming * gains.incoming, 1, accuracy: 0.0001)
        }
    }

    func testBundledMusicActuallyDecodesAndCrossfadesAtTheScheduledBoundary() throws {
        let urls = try SoundtrackTrack.bundled.map { track in
            try XCTUnwrap(Bundle.main.url(forResource: track.resource, withExtension: "m4a", subdirectory: "Assets/Music"),
                          "Both requested songs must be bundled for offline playback.")
        }
        var planner = SoundtrackPlanner(seed: 17)
        let first = try XCTUnwrap(planner.next())
        let second = try XCTUnwrap(planner.next())
        let renderer = try SoundtrackPCMRenderer(urls: urls)
        let firstOutput = try renderer.render(first)
        let secondOutput = try renderer.render(second)
        XCTAssertEqual(firstOutput.frameLength, first.frameCount)
        XCTAssertEqual(secondOutput.frameLength, second.frameCount)
        let firstData = try XCTUnwrap(firstOutput.floatChannelData)
        let secondData = try XCTUnwrap(secondOutput.floatChannelData)
        XCTAssertEqual(firstData[0][0], 0, accuracy: 0.0001, "The initial attack should have a short click-free fade.")

        let outgoingFile = try AVAudioFile(forReading: urls[first.trackIndex], commonFormat: .pcmFormatFloat32, interleaved: false)
        outgoingFile.framePosition = first.sourceStartFrame + Int64(first.frameCount)
        let outgoing = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outgoingFile.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(SoundtrackCrossfade.frameCount)))
        try outgoingFile.read(into: outgoing)
        let outgoingData = try XCTUnwrap(outgoing.floatChannelData)
        for channel in 0..<2 {
            XCTAssertEqual(secondData[channel][0], outgoingData[channel][0], accuracy: 0.0001,
                           "A cut must carry the outgoing track's natural tail into the incoming bars.")
            var energy: Float = 0
            var samples = 0
            for frame in stride(from: 0, to: Int(secondOutput.frameLength), by: 113) {
                let value = secondData[channel][frame]
                XCTAssertTrue(value.isFinite)
                XCTAssertLessThanOrEqual(abs(value), 1, "Prepared sources and equal-power overlap must not clip.")
                energy += value * value
                samples += 1
            }
            XCTAssertGreaterThan(energy / Float(samples), 0.000001, "The scheduled piece must contain actual music.")
        }
    }

    func testGaragePurchaseRequiresCashAndChargesEachTierOnce() {
        let garage = GarageProgress(defaults: nil)
        XCTAssertFalse(garage.purchase(.armor))
        XCTAssertEqual(garage.wallet, 0)
        XCTAssertEqual(garage.level(for: .armor), 0)

        garage.award(distanceCash: 200)
        XCTAssertTrue(garage.purchase(.armor))
        XCTAssertEqual(garage.wallet, 170)
        XCTAssertEqual(garage.level(for: .armor), 1)
        XCTAssertEqual(garage.cost(for: .armor), 60)
        XCTAssertTrue(garage.purchase(.armor))
        XCTAssertTrue(garage.purchase(.armor))
        XCTAssertEqual(garage.level(for: .armor), GarageProgress.maximumLevel)
        XCTAssertEqual(garage.wallet, 20)
        XCTAssertNil(garage.cost(for: .armor))
        XCTAssertFalse(garage.purchase(.armor))
        XCTAssertEqual(garage.wallet, 20, "A maxed upgrade must not charge again.")
        XCTAssertFalse(garage.purchase(.engine))
        XCTAssertEqual(garage.level(for: .engine), 0)
        XCTAssertEqual(garage.wallet, 20, "An unaffordable purchase must leave the profile unchanged.")
    }

    func testGarageEarningsAndPurchasesPersistTogether() throws {
        let suite = "TheDriveTests.garage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let garage = GarageProgress(defaults: defaults)
        garage.award(distanceCash: 150)
        XCTAssertTrue(garage.purchase(.engine))
        XCTAssertTrue(garage.purchase(.magazine))

        let restored = GarageProgress(defaults: defaults)
        XCTAssertEqual(restored.wallet, 70)
        XCTAssertEqual(restored.level(for: .engine), 1)
        XCTAssertEqual(restored.level(for: .magazine), 1)
        XCTAssertEqual(restored.level(for: .armor), 0)
        XCTAssertEqual(restored.cost(for: .engine), 90)
    }

    func testGarageRejectsNegativeAwardsAndBoundsSavedUpgradeLevels() throws {
        let suite = "TheDriveTests.garage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["wallet": -80, "armor": -3, "engine": 100, "magazine": 2],
                     forKey: "TheDrive.garage.v1")
        let garage = GarageProgress(defaults: defaults)
        XCTAssertEqual(garage.wallet, 0)
        XCTAssertEqual(garage.level(for: .armor), 0)
        XCTAssertEqual(garage.level(for: .engine), 3)
        XCTAssertEqual(garage.level(for: .magazine), 2)
        garage.award(distanceCash: -10)
        garage.award(distanceCash: 0)
        XCTAssertEqual(garage.wallet, 0)
        garage.award(distanceCash: Int.max)
        garage.award(distanceCash: 1)
        XCTAssertEqual(garage.wallet, Int.max, "A long-lived profile must never overflow into negative cash.")
    }

    func testMarketPreviewDrivesWithoutSpendingRunState() {
        let game = GameModel(seed: 0xBA2AA2)
        let camera = game.cameraNode.position
        advance(game, from: 0, seconds: 2)

        XCTAssertFalse(game.started)
        XCTAssertFalse(game.isInCutscene)
        XCTAssertFalse(game.isGameOver)
        XCTAssertFalse(game.isCrashing)
        XCTAssertEqual(game.distance, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.health, 1)
        XCTAssertEqual(game.simulationClock, 0)
        XCTAssertNotEqual([camera.x, camera.y, camera.z],
                          [game.cameraNode.position.x, game.cameraNode.position.y, game.cameraNode.position.z],
                          "The title screen should show a moving drive through the bazaar.")
    }

    func testOpeningKeepsPlayerSafeAndLocksCombatUntilHandover() {
        let game = GameModel(seed: 17)
        game.beginOpening()
        XCTAssertTrue(game.isInCutscene)
        game.toggleGunner()
        game.setSteering(1)
        game.setFiring(true)
        advance(game, from: 0, seconds: 2)

        XCTAssertFalse(game.started)
        XCTAssertTrue(game.isInCutscene)
        XCTAssertGreaterThan(game.openingProgress, 0)
        XCTAssertLessThan(game.openingProgress, 1)
        XCTAssertFalse(game.isGunning)
        XCTAssertFalse(game.isTransitioning)
        XCTAssertEqual(game.shotsFired, 0)
        XCTAssertEqual(game.distance, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.health, 1)
        XCTAssertEqual(game.simulationClock, 0)
    }

    func testOpeningAutomaticallyHandsOverWithFreshRunCounters() {
        let game = GameModel(seed: 17)
        game.beginOpening()
        game.update(time: 0)
        for frame in 1...720 where !game.started {
            game.update(time: Double(frame) / 60)
        }

        XCTAssertTrue(game.started, "The opening should finish without another tap.")
        XCTAssertFalse(game.isInCutscene)
        XCTAssertEqual(game.distance, 0, "The cinematic distance is not part of the player's run.")
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.health, 1)
        XCTAssertEqual(game.simulationClock, 0, accuracy: 0.02)
        game.update(time: 30)
        advance(game, from: 30, seconds: 0.5)
        XCTAssertGreaterThan(game.distance, 0, "Gameplay must advance normally after the handover.")
        XCTAssertFalse(game.isGameOver)
    }

    func testSkipOpeningStartsImmediatelyAndPreservesRouteSeed() {
        let game = GameModel(seed: 0xBA2AA2)
        advance(game, from: 0, seconds: 4)
        let seed = game.seed
        game.beginOpening()
        advance(game, from: 4, seconds: 0.5)
        game.skipOpening()

        XCTAssertTrue(game.started)
        XCTAssertFalse(game.isInCutscene)
        XCTAssertEqual(game.seed, seed)
        XCTAssertEqual(game.distance, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.simulationClock, 0)
        XCTAssertEqual(game.health, 1)
        game.skipOpening()
        XCTAssertTrue(game.started, "An extra skip must not restart the run.")
        advance(game, from: 4.5, seconds: 0.5)
        XCTAssertGreaterThan(game.distance, 0)
    }

    func testPauseFreezesOpeningAndResumeDoesNotJumpToItsEnd() {
        let game = GameModel(seed: 17)
        game.beginOpening()
        advance(game, from: 0, seconds: 0.75)
        let progress = game.openingProgress
        let camera = game.cameraNode.position
        game.setPaused(true)
        advance(game, from: 0.75, seconds: 5)

        XCTAssertEqual(game.openingProgress, progress)
        XCTAssertEqual([game.cameraNode.position.x, game.cameraNode.position.y, game.cameraNode.position.z],
                       [camera.x, camera.y, camera.z])
        game.setPaused(false)
        game.update(time: 100)
        XCTAssertEqual(game.openingProgress, progress)
        advance(game, from: 100, seconds: 0.25)
        XCTAssertTrue(game.isInCutscene)
        XCTAssertGreaterThan(game.openingProgress, progress)
        XCTAssertLessThan(game.openingProgress - progress, 0.1)
    }

    func testOnlyDrivingEarnsCashAndRestartKeepsTheWallet() {
        let garage = GarageProgress(defaults: nil)
        let game = GameModel(seed: 17, garage: garage)
        advance(game, from: 0, seconds: 3)
        game.beginOpening()
        advance(game, from: 3, seconds: 2)
        XCTAssertEqual(game.runCash, 0)
        XCTAssertEqual(garage.wallet, 0, "Watching the market must not farm cash.")

        game.skipOpening()
        advance(game, from: 5, seconds: 1.3)
        XCTAssertEqual(game.runCash, 2)
        XCTAssertEqual(garage.wallet, game.runCash)
        let earned = garage.wallet
        game.setPaused(true)
        advance(game, from: 6.3, seconds: 3)
        XCTAssertEqual(garage.wallet, earned)
        game.restart()
        XCTAssertEqual(game.runCash, 0)
        XCTAssertEqual(garage.wallet, earned)
        advance(game, from: 10, seconds: 1.3)
        XCTAssertEqual(garage.wallet, earned + game.runCash,
                       "Each run should award only its newly earned cash.")
    }

    func testPurchasedUpgradesApplyToTheNextRunAndStayFixedDuringDriving() {
        let garage = GarageProgress(defaults: nil)
        garage.award(distanceCash: 500)
        XCTAssertTrue(garage.purchase(.engine))
        XCTAssertTrue(garage.purchase(.magazine))
        XCTAssertTrue(garage.purchase(.magazine))
        let upgraded = GameModel(seed: 17, garage: garage)
        let stock = GameModel(seed: 17)
        upgraded.start()
        stock.start()
        XCTAssertEqual(upgraded.magazineCapacity, 32)
        XCTAssertEqual(upgraded.ammo, 32)
        XCTAssertEqual(upgraded.speed, 76)
        advance(upgraded, from: 0, seconds: 1.3)
        advance(stock, from: 0, seconds: 1.3)
        XCTAssertGreaterThan(upgraded.distance, stock.distance,
                             "The engine purchase must change actual movement, not only the speed label.")

        XCTAssertTrue(garage.purchase(.magazine))
        XCTAssertEqual(upgraded.magazineCapacity, 32, "Purchases cannot change a live run's loadout.")
        upgraded.restart()
        XCTAssertEqual(upgraded.magazineCapacity, 36)
        XCTAssertEqual(upgraded.ammo, 36)
    }

    func testExtendedMagazineReloadsToItsPurchasedCapacity() {
        let garage = GarageProgress(defaults: nil)
        garage.award(distanceCash: 35)
        XCTAssertTrue(garage.purchase(.magazine))
        let game = GameModel(seed: 17, garage: garage)
        game.start()
        game.toggleGunner()
        advance(game, from: 0, seconds: 1.3)
        game.setAimRay(origin: SCNVector3(0, 2, -5), direction: SCNVector3(0, 1, 0))
        game.setFiring(true)
        advance(game, from: 1.3, seconds: 0.4)
        game.setFiring(false)
        XCTAssertGreaterThan(game.shotsFired, 0)
        XCTAssertLessThan(game.ammo, 28)
        game.reload()
        XCTAssertTrue(game.isReloading)
        advance(game, from: 1.7, seconds: 1.6)
        XCTAssertFalse(game.isReloading)
        XCTAssertEqual(game.ammo, 28)
    }

    private func advance(_ game: GameModel, from start: TimeInterval, seconds: TimeInterval) {
        game.update(time: start)
        for frame in 1...max(1, Int((seconds * 60).rounded())) {
            game.update(time: start + Double(frame) / 60)
        }
    }

    private var musicFixtures: [SoundtrackTrack] {
        [SoundtrackTrack(id: "a", resource: "a", firstDownbeat: 1, bpm: 120, duration: 60),
         SoundtrackTrack(id: "b", resource: "b", firstDownbeat: 2, bpm: 120, duration: 42)]
    }

    private func musicSignature(_ piece: SoundtrackPiece) -> String {
        "\(piece.trackIndex):\(piece.startBar):\(piece.barCount):\(piece.sourceStartFrame):\(piece.frameCount):\(piece.timelineStartFrame)"
    }
}
