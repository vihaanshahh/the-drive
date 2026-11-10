import XCTest
import SceneKit
import UIKit
@testable import TheDrive

@MainActor
final class GameModelTests: XCTestCase {
    func testPauseFreezesRunAndResumeDoesNotJumpForward() {
        let game = GameModel()
        game.start()
        advance(game, from: 0, seconds: 1)
        XCTAssertGreaterThan(game.distance, 0)
        let distanceBeforePause = game.distance
        let cameraBeforePause = game.cameraNode.position

        game.setPaused(true)
        advance(game, from: 1, seconds: 2)
        XCTAssertEqual(game.distance, distanceBeforePause)
        XCTAssertEqual(game.cameraNode.position.z, cameraBeforePause.z)

        game.setPaused(false)
        game.update(time: 300)
        XCTAssertEqual(game.distance, distanceBeforePause, "The first frame after resume must rebase the clock.")
        advance(game, from: 300, seconds: 0.5)
        XCTAssertGreaterThan(game.distance, distanceBeforePause)
        XCTAssertLessThan(game.distance - distanceBeforePause, 15)
    }

    func testManualAimCanMissAndTrackingRayCanDisablePursuer() {
        let game = readyGunner(seed: 17)
        game.setAimRay(origin: SCNVector3(0, 2, -5), direction: SCNVector3(0, 1, 0))
        game.setFiring(true)
        advance(game, from: 1.3, seconds: 0.5)
        XCTAssertGreaterThan(game.shotsFired, 0)
        XCTAssertEqual(game.hits, 0, "Holding fire must not automatically select a pursuer.")
        XCTAssertEqual(game.kills, 0)

        for frame in 1...90 {
            if let target = game.enemyPositions.first {
                game.setAimRay(origin: SCNVector3(0, 2, -5),
                               direction: SCNVector3(target.x, target.y - 0.9, target.z + 5))
            }
            game.update(time: 1.8 + Double(frame) / 60)
        }
        game.setFiring(false)
        advance(game, from: 3.3, seconds: 0.2)
        XCTAssertGreaterThan(game.hits, 0)
        XCTAssertGreaterThan(game.kills, 0)
        XCTAssertGreaterThanOrEqual(game.score, game.distance + game.kills * 150)
        XCTAssertFalse(game.isGameOver)
    }

    func testTransferLocksWeaponPausesAndReturnsToDriving() {
        let game = GameModel(seed: 17)
        game.start()
        game.toggleGunner()
        XCTAssertTrue(game.isTransitioning)
        game.setAimRay(origin: SCNVector3(0, 2, -5), direction: SCNVector3(0, 0, 1))
        game.setFiring(true)
        advance(game, from: 0, seconds: 0.5)
        XCTAssertTrue(game.isTransitioning)
        XCTAssertGreaterThan(game.transitionProgress, 0)
        XCTAssertLessThan(game.transitionProgress, 1)
        XCTAssertEqual(game.shotsFired, 0)
        let progress = game.transitionProgress
        game.setPaused(true)
        advance(game, from: 0.5, seconds: 1)
        XCTAssertEqual(game.transitionProgress, progress)
        game.setPaused(false)
        advance(game, from: 1.5, seconds: 0.8)
        XCTAssertFalse(game.isTransitioning)
        XCTAssertEqual(game.transitionProgress, 1)

        game.toggleGunner()
        advance(game, from: 2.3, seconds: 0.5)
        XCTAssertTrue(game.isTransitioning)
        XCTAssertGreaterThan(game.transitionProgress, 0)
        XCTAssertLessThan(game.transitionProgress, 1)
        advance(game, from: 2.8, seconds: 0.8)
        XCTAssertFalse(game.isTransitioning)
        XCTAssertFalse(game.isGunning)
        XCTAssertEqual(game.transitionProgress, 0)
    }

    func testEmptyMagazineReloadsAndPauseFreezesReloadTimer() {
        let game = readyGunner(seed: 17)
        game.setAimRay(origin: SCNVector3(0, 2, -5), direction: SCNVector3(0, 1, 0))
        game.setFiring(true)
        var time = 1.3
        while !game.isReloading && time < 6 {
            time += 1.0 / 60
            game.update(time: time)
        }
        XCTAssertTrue(game.isReloading)
        XCTAssertEqual(game.ammo, 0)
        XCTAssertEqual(game.shotsFired, 24)
        game.setFiring(false)
        game.setPaused(true)
        advance(game, from: time, seconds: 2)
        XCTAssertTrue(game.isReloading)
        XCTAssertEqual(game.ammo, 0)
        game.setPaused(false)
        advance(game, from: time + 2, seconds: 1)
        XCTAssertTrue(game.isReloading)
        advance(game, from: time + 3, seconds: 0.6)
        XCTAssertFalse(game.isReloading)
        XCTAssertEqual(game.ammo, 24)
        XCTAssertEqual(game.tracerCount, 12)
    }

    func testPursuersDodgeWhenThreatenedByGunfire() {
        let threatened = readyGunner(seed: 17)
        let unthreatened = readyGunner(seed: 17)
        threatened.setAimRay(origin: SCNVector3(0, 2, -5), direction: SCNVector3(0, 1, 0))
        threatened.setFiring(true)
        advance(threatened, from: 1.3, seconds: 0.8)
        advance(unthreatened, from: 1.3, seconds: 0.8)
        let differences = zip(threatened.enemyPositions, unthreatened.enemyPositions).map { abs($0.x - $1.x) }
        XCTAssertTrue(differences.contains { $0 > 0.2 }, "Gunfire should cause actual evasive movement.")
        XCTAssertEqual(threatened.hits, 0)
    }

    func testRoadRecyclingKeepsSixContiguousChunks() throws {
        let game = GameModel()
        game.start()
        advance(game, from: 0, seconds: 6)
        XCTAssertGreaterThan(game.distance, 115)
        XCTAssertFalse(game.isGameOver)

        let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
        let chunks = world.childNodes.filter { node in
            guard let ground = node.childNodes.first?.geometry as? SCNBox else { return false }
            return ground.width == 80 && ground.length == 48
        }
        XCTAssertEqual(chunks.count, 6, "Endless scenery should recycle instead of accumulating chunks.")
        let positions = chunks.map(\.position.z).sorted()
        for pair in zip(positions, positions.dropFirst()) {
            XCTAssertEqual(pair.1 - pair.0, 48, accuracy: 0.01, "Recycled road tiles must meet without gaps.")
        }
        XCTAssertTrue(positions.allSatisfy { $0 >= -240 && $0 <= 80 })
    }

    func testChunkGeometryIsReproducibleAndSeedChangesRoute() {
        let first = WorldBuilder.makeChunk(index: 7, seed: 0xD351, night: false)
        let replay = WorldBuilder.makeChunk(index: 7, seed: 0xD351, night: false)
        let different = WorldBuilder.makeChunk(index: 7, seed: 0xD352, night: false)
        XCTAssertEqual(geometrySignature(first), geometrySignature(replay))
        XCTAssertNotEqual(geometrySignature(first), geometrySignature(different))
    }

    func testNightToggleSwitchesHeadlightsAndStreetLamps() {
        let game = GameModel()
        var headlights: [SCNLight] = []
        var streetLamps: [SCNLight] = []
        game.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "headlight", let light = node.light { headlights.append(light) }
            if node.name == "streetLight", let light = node.light { streetLamps.append(light) }
        }
        XCTAssertFalse(headlights.isEmpty)
        XCTAssertFalse(streetLamps.isEmpty)
        XCTAssertTrue(headlights.allSatisfy { $0.intensity == 0 })

        game.toggleNight()
        XCTAssertTrue(game.isNight)
        XCTAssertTrue(headlights.allSatisfy { $0.intensity > 0 })
        XCTAssertTrue(streetLamps.allSatisfy { $0.intensity > 0 })
        game.toggleNight()
        XCTAssertFalse(game.isNight)
        XCTAssertTrue(headlights.allSatisfy { $0.intensity == 0 })
        XCTAssertTrue(streetLamps.allSatisfy { $0.intensity == 0 })
    }

    func testRestartClearsPreviousRun() {
        let game = GameModel()
        game.start()
        game.toggleGunner()
        advance(game, from: 0, seconds: 2)
        XCTAssertGreaterThan(game.distance, 0)
        game.setPaused(true)
        game.restart()
        XCTAssertTrue(game.started)
        XCTAssertFalse(game.isPaused)
        XCTAssertFalse(game.isGunning)
        XCTAssertFalse(game.isGameOver)
        XCTAssertEqual(game.distance, 0)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.kills, 0)
        XCTAssertEqual(game.health, 1)
        XCTAssertEqual(game.speed, 72)
    }

    func testRearCameraFacesPursuitAndTracksSteering() {
        let game = GameModel()
        let initialX = game.rearCameraNode.position.x
        game.start()
        game.steer(1)
        advance(game, from: 0, seconds: 1)

        XCTAssertGreaterThan(game.rearCameraNode.position.x, initialX + 1)
        XCTAssertGreaterThan(game.rearCameraNode.simdWorldFront.z, 0.9,
                             "Rear capture must look toward pursuers behind the jeep.")
        XCTAssertLessThanOrEqual(game.rearCameraNode.camera?.zFar ?? .infinity, 100,
                                 "The small rear view should use a bounded draw distance.")
        game.toggleGunner()
        advance(game, from: 1, seconds: 2)
        XCTAssertGreaterThan(game.rearCameraNode.simdWorldFront.z, 0.9)
        XCTAssertLessThan(game.roadCameraNode.simdWorldFront.z, -0.9,
                          "Sunglass preview should show approaching road hazards during rear gun mode.")
        XCTAssertGreaterThan(game.cameraNode.simdWorldFront.z, 0.9)
    }

    func testHeroSunglassesAreUnavailableAtNight() throws {
        let game = GameModel()
        let driver = try XCTUnwrap(game.scene.rootNode.childNode(withName: "playerDriver", recursively: true))
        let glasses = try XCTUnwrap(driver.childNode(withName: "sunglasses", recursively: true))
        XCTAssertFalse(glasses.isHidden)
        var lensCount = 0
        glasses.enumerateChildNodes { node, _ in
            if node.name == "sunglassLens" {
                lensCount += 1
                XCTAssertEqual(node.categoryBitMask & (game.rearCameraNode.camera?.categoryBitMask ?? 1), 0,
                               "Capture cameras must exclude reflection lenses to avoid feedback.")
            }
        }
        XCTAssertGreaterThan(lensCount, 0)
        game.toggleNight()
        XCTAssertTrue(glasses.isHidden)
        game.toggleNight()
        XCTAssertFalse(glasses.isHidden)
    }

    func testVehicleAnimationKeepsDustEmittersBounded() throws {
        let game = GameModel()
        let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
        let jeep = try XCTUnwrap(world.childNodes.first { node in
            node.childNode(withName: "playerDriver", recursively: true) != nil
        })
        func dustEmitters() -> [SCNParticleSystem] {
            var emitters: [SCNParticleSystem] = []
            jeep.enumerateChildNodes { node, _ in
                if node.name == "vehicleDust" { emitters += node.particleSystems ?? [] }
            }
            return emitters
        }
        let initial = dustEmitters()
        XCTAssertFalse(initial.isEmpty)
        game.start()
        advance(game, from: 0, seconds: 4)
        let afterDriving = dustEmitters()
        XCTAssertEqual(afterDriving.count, initial.count,
                       "Animation must reuse emitters instead of adding one each frame.")
        for emitter in afterDriving {
            XCTAssertGreaterThan(emitter.particleLifeSpan, 0)
            XCTAssertLessThanOrEqual(emitter.birthRate * emitter.particleLifeSpan, 250,
                                     "Dust should have a bounded steady-state particle budget.")
        }
    }

    func testProceduralTexturesUseMetalCompatibleRGBAImages() throws {
        let scene = SCNScene()
        scene.rootNode.addChildNode(WorldBuilder.makeChunk(index: 0, seed: 17, night: false))
        WorldBuilder.configureEnvironment(scene: scene, night: false)
        var images: [UIImage] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
                    if let image = property.contents as? UIImage { images.append(image) }
                }
            }
            for particles in node.particleSystems ?? [] {
                if let image = particles.particleImage as? UIImage { images.append(image) }
            }
        }
        WorldBuilder.makeJeep().enumerateChildNodes { node, _ in
            for particles in node.particleSystems ?? [] {
                if let image = particles.particleImage as? UIImage { images.append(image) }
            }
        }
        if let image = scene.background.contents as? UIImage { images.append(image) }
        if let image = scene.lightingEnvironment.contents as? UIImage { images.append(image) }
        XCTAssertGreaterThan(images.count, 5, "Exercise vehicle, ground, dust, and environment textures.")
        for image in images {
            let bitmap = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(bitmap.bitsPerComponent, 8)
            XCTAssertEqual(bitmap.bitsPerPixel, 32,
                           "Grayscale textures can select unsupported R8 sRGB formats in SceneKit Metal.")
            XCTAssertEqual(bitmap.colorSpace?.model, .rgb)
        }
    }

    func testSeededRestartsKeepSceneAndTracerPoolBounded() {
        let game = GameModel(seed: 17)
        let initialCount = descendantCount(game.scene.rootNode)
        for _ in 0..<12 {
            game.restart()
            advance(game, from: 0, seconds: 6)
            XCTAssertFalse(game.isGameOver)
            XCTAssertEqual(game.tracerCount, 12)
            XCTAssertLessThan(descendantCount(game.scene.rootNode), initialCount * 2,
                              "Recycling and restarting must release old scenery and pooled effects.")
        }
        game.restart()
        XCTAssertEqual(descendantCount(game.scene.rootNode), initialCount)
    }

    func testGeneratedChunksShareTextureResources() {
        func images(in node: SCNNode) -> Set<ObjectIdentifier> {
            var identities = Set<ObjectIdentifier>()
            node.enumerateChildNodes { child, _ in
                for material in child.geometry?.materials ?? [] {
                    for property in [material.diffuse, material.normal] {
                        if let image = property.contents as? UIImage {
                            identities.insert(ObjectIdentifier(image))
                        }
                    }
                }
            }
            return identities
        }
        let first = WorldBuilder.makeChunk(index: 0, seed: 17, night: false)
        let initialImages = images(in: first)
        XCTAssertFalse(initialImages.isEmpty)
        for index in 1...20 {
            let chunk = WorldBuilder.makeChunk(index: index, seed: 17, night: false)
            XCTAssertTrue(images(in: chunk).isSubset(of: initialImages),
                          "New route chunks should reuse cached texture images.")
        }
    }

    func testSameDriverTransfersToGunAndReturnsToSeat() throws {
        let game = GameModel(seed: 17)
        let driver = try XCTUnwrap(game.scene.rootNode.childNode(withName: "playerDriver", recursively: true))
        let seated = driver.position
        var skins: [SCNSkinner] = []
        driver.enumerateChildNodes { node, _ in
            if let skin = node.skinner { skins.append(skin) }
        }
        XCTAssertFalse(skins.isEmpty, "The bundled character mesh must load with its skeleton.")
        game.start()
        game.toggleGunner()
        advance(game, from: 0, seconds: 1.3)
        let dx = driver.position.x - seated.x
        let dy = driver.position.y - seated.y
        let dz = driver.position.z - seated.z
        XCTAssertGreaterThan(sqrt(dx * dx + dy * dy + dz * dz), 0.5,
                             "The actor must physically move from the seat to the gun.")
        for skin in skins {
            XCTAssertFalse(skin.bones.isEmpty)
            for bone in skin.bones {
                let transform = bone.simdWorldTransform
                for column in 0..<4 {
                    for row in 0..<4 { XCTAssertTrue(transform[column][row].isFinite) }
                }
            }
        }
        game.toggleGunner()
        advance(game, from: 1.3, seconds: 1.3)
        XCTAssertEqual(driver.position.x, seated.x, accuracy: 0.05)
        XCTAssertEqual(driver.position.y, seated.y, accuracy: 0.05)
        XCTAssertEqual(driver.position.z, seated.z, accuracy: 0.05)
        var actorCount = 0
        game.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "playerDriver" { actorCount += 1 }
        }
        XCTAssertEqual(actorCount, 1, "Transfer must animate the same actor, without leaving a seated duplicate.")
    }

    func testAimProjectionProducesForwardRayWithEitherDepthConvention() {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
        let target = SCNVector3(1, 1, -10)
        for reverseDepth in [false, true] {
            view.usesReverseZ = reverseDepth
            let projected = view.projectPoint(target)
            let point = CGPoint(x: CGFloat(projected.x) / view.bounds.width,
                                y: CGFloat(projected.y) / view.bounds.height)
            let ray = AimProjection.ray(in: view, at: point)
            let direction = SIMD3(ray.direction.x, ray.direction.y, ray.direction.z)
            let origin = SIMD3(ray.origin.x, ray.origin.y, ray.origin.z)
            let delta = SIMD3(target.x, target.y, target.z) - origin
            let forward = simd_normalize(direction)
            XCTAssertGreaterThan(simd_dot(delta, forward), 0,
                                 "A reverse-depth camera must still fire into the visible scene.")
            let miss = delta - forward * simd_dot(delta, forward)
            XCTAssertLessThan(simd_length(miss), 0.01)
            XCTAssertLessThan(simd_length(origin), 1, "Ray origin should be at the near clip plane.")
        }
        let upperRight = AimProjection.ray(in: view, at: CGPoint(x: 0.75, y: 0.25))
        XCTAssertGreaterThan(upperRight.direction.x, 0)
        XCTAssertGreaterThan(upperRight.direction.y, 0,
                             "Dragging the UIKit reticle upward must aim above the camera center.")
        XCTAssertLessThan(upperRight.direction.z, 0)
    }

    func testCrashMotionRisesTumblesBouncesAndSettles() {
        for kind in 0...2 {
            for cause in [CrashCause.shot, .roadblock, .shoulder] {
                for side: Float in [-1, 1] {
                    let motion = CrashMotion(start: SCNVector3(1, 0, 20), kind: kind, side: side, cause: cause)
                    let launch = motion.sample(age: 0)
                    let airborne = motion.sample(age: 0.6)
                    let landed = motion.sample(age: 2.3)
                    let settled = motion.sample(age: 3.1)
                    let later = motion.sample(age: 4)
                    XCTAssertFalse(airborne.isLanded)
                    XCTAssertGreaterThan(airborne.position.y, launch.position.y + 1)
                    XCTAssertGreaterThan(abs(airborne.angles.z), .pi / 2)
                    XCTAssertTrue(landed.isLanded)
                    XCTAssertTrue(settled.isLanded)
                    for frame in 0...240 {
                        XCTAssertLessThanOrEqual(abs(motion.sample(age: Float(frame) / 60).position.x), 6.601,
                                                 "Wrecks must stay on the shoulder before building fronts.")
                    }
                    XCTAssertLessThan(settled.position.y, airborne.position.y)
                    XCTAssertEqual(settled.position.x, later.position.x, accuracy: 0.001)
                    XCTAssertEqual(settled.position.y, later.position.y, accuracy: 0.001)
                    XCTAssertEqual(settled.position.z, later.position.z, accuracy: 0.001)
                    for value in [airborne.position.x, airborne.position.y, airborne.position.z,
                                  airborne.angles.x, airborne.angles.y, airborne.angles.z] {
                        XCTAssertTrue(value.isFinite)
                    }
                }
            }
        }
        attachRolloverPreview(age: 0.6, name: "Rally car airborne rollover")
        attachRolloverPreview(age: 2.6, name: "Rally car landing and slide")
    }

    func testShotWreckFreezesWhenPausedAndExpiresWithoutRendererActions() throws {
        let game = readyGunner(seed: 17)
        game.setFiring(true)
        var time = 1.3
        while game.kills == 0 && time < 3 {
            if let target = game.enemyPositions.first {
                game.setAimRay(origin: SCNVector3(0, 2, -5),
                               direction: SCNVector3(target.x, target.y - 0.9, target.z + 5))
            }
            time += 1.0 / 60
            game.update(time: time)
        }
        game.setFiring(false)
        XCTAssertGreaterThan(game.kills, 0)
        XCTAssertGreaterThan(game.activeWreckCount, 0)
        advance(game, from: time, seconds: 0.3)
        let position = try XCTUnwrap(game.wreckPositions.first)
        let angles = try XCTUnwrap(game.wreckAngles.first)
        XCTAssertGreaterThan(position.y, 1)
        XCTAssertGreaterThan(abs(angles.z), 0.3)
        game.setPaused(true)
        advance(game, from: time + 0.3, seconds: 2)
        let frozenPosition = try XCTUnwrap(game.wreckPositions.first)
        let frozenAngles = try XCTUnwrap(game.wreckAngles.first)
        XCTAssertEqual([frozenPosition.x, frozenPosition.y, frozenPosition.z], [position.x, position.y, position.z])
        XCTAssertEqual([frozenAngles.x, frozenAngles.y, frozenAngles.z], [angles.x, angles.y, angles.z])
        game.setPaused(false)
        advance(game, from: time + 2.3, seconds: 3.5)
        XCTAssertEqual(game.activeWreckCount, 0, "Simulation time must remove wrecks without a running renderer.")
        XCTAssertTrue(game.wreckPositions.isEmpty)
        XCTAssertTrue(game.wreckAngles.isEmpty)
    }

    func testRoadblockRemovesPursuerBeforeItCanCatchPlayer() throws {
        let game = GameModel(seed: 17)
        game.start()
        advance(game, from: 0, seconds: 2)
        let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
        let hazard = try XCTUnwrap(world.childNodes.first { $0.name == "roadHazard" })
        let pursuer = try XCTUnwrap(world.childNodes.first { $0.name == "pursuer" })
        let before = game.enemyPositions.count
        // Use a real spawned roadblock, just in front of the catching pursuer.
        pursuer.position = SCNVector3(3.6, 0, 3.11)
        hazard.position = SCNVector3(3.6, 0, 3.11)
        game.update(time: 2 + 1.0 / 60)
        XCTAssertEqual(game.enemyPositions.count, before - 1)
        XCTAssertGreaterThan(game.activeWreckCount, 0)
        XCTAssertFalse(game.isGameOver, "A pursuer wrecked by debris must not also catch the jeep.")
    }

    func testFatalRoadImpactsShowCrashBeforeGameOverAndPauseFreezesIt() throws {
        let game = GameModel(seed: 17)
        game.start()
        game.update(time: 0)
        let world = try XCTUnwrap(game.scene.rootNode.childNodes.first)
        var time = 0.0
        while !game.isCrashing && !game.isGameOver && time < 30 {
            // Isolate road-impact failure from the separate catch-up failure condition.
            for node in world.childNodes where node.name == "pursuer" { node.position.z = 200 }
            for node in world.childNodes where node.name == "roadHazard" || node.name == "pedestrianHazard" {
                node.position = SCNVector3(0, 0, -1)
                node.name = "testedImpact"
            }
            time += 1.0 / 60
            game.update(time: time)
        }
        XCTAssertTrue(game.isCrashing)
        XCTAssertFalse(game.isGameOver, "The visible rollover should finish before the retry screen appears.")
        XCTAssertEqual(game.health, 0)
        game.setPaused(true)
        advance(game, from: time, seconds: 2)
        XCTAssertTrue(game.isCrashing)
        XCTAssertFalse(game.isGameOver)
        game.setPaused(false)
        advance(game, from: time + 2, seconds: 1.6)
        XCTAssertFalse(game.isCrashing)
        XCTAssertTrue(game.isGameOver)
    }

    private func attachRolloverPreview(age: Float, name: String) {
        let scene = SCNScene()
        scene.rootNode.addChildNode(WorldBuilder.makeChunk(index: 0, seed: 17, night: false))
        WorldBuilder.configureEnvironment(scene: scene, night: false)
        let motion = CrashMotion(start: SCNVector3Zero, kind: 1, side: 1, cause: .roadblock)
        let pose = motion.sample(age: age)
        let pivot = SCNNode()
        pivot.position = pose.position
        pivot.eulerAngles = pose.angles
        let car = WorldBuilder.makePursuer(kind: 1)
        car.position.y = -0.85
        pivot.addChildNode(car)
        scene.rootNode.addChildNode(pivot)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .ambient
        light.light?.intensity = 700
        scene.rootNode.addChildNode(light)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(pose.position.x + 7, 5, pose.position.z + 9)
        camera.look(at: pose.position, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1024, height: 512), antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPursuitBikeUsesTheImportedRiderAndWheels() throws {
        let bike = WorldBuilder.makePursuer(kind: 0)
        let suspension = try XCTUnwrap(bike.childNode(withName: "suspension", recursively: false))
        XCTAssertNotNil(suspension.childNode(withName: "importedVehicleMesh", recursively: false))
        XCTAssertNotNil(suspension.childNode(withName: "pursuerRider", recursively: true))
        let wheels = bike.childNodes.filter { $0.name == "wheel" }
        XCTAssertEqual(wheels.count, 2)
        let front = try XCTUnwrap(wheels.first { $0.position.z < 0 })
        XCTAssertEqual(wheels.filter { $0.position.z > 0 }.count, 1)
        WorldBuilder.animateVehicle(bike, time: 0, speed: 16, steering: 0.7)
        for frame in 1...20 {
            WorldBuilder.animateVehicle(bike, time: Float(frame) / 60, speed: 16, steering: 0.7)
        }
        XCTAssertLessThan(front.eulerAngles.y, 0)
        XCTAssertNotEqual(front.eulerAngles.x, 0)
        let axle = front.convertVector(SCNVector3(1, 0, 0), to: bike)
        XCTAssertGreaterThan(axle.z, 0)
    }

    func testImportedPursuersHaveSeparateSteeringAndSpinningWheels() throws {
        for kind in [1, 2] {
            let vehicle = WorldBuilder.makePursuer(kind: kind)
            let suspension = try XCTUnwrap(vehicle.childNode(withName: "suspension", recursively: false))
            let body = try XCTUnwrap(suspension.childNode(withName: "importedVehicleMesh", recursively: false),
                                     "The bundled vehicle asset must load instead of the fallback body.")
            XCTAssertNotNil(body.geometry)
            let wheels = vehicle.childNodes.filter { $0.name == "wheel" }
            XCTAssertEqual(wheels.count, 4)
            let front = wheels.filter { $0.position.z < 0 }
            let rear = wheels.filter { $0.position.z > 0 }
            XCTAssertEqual(front.count, 2)
            XCTAssertEqual(rear.count, 2)

            WorldBuilder.animateVehicle(vehicle, time: 0, speed: 20, steering: 0.8)
            for frame in 1...30 {
                WorldBuilder.animateVehicle(vehicle, time: Float(frame) / 60, speed: 20, steering: 0.8)
            }
            // Vehicles face -Z. Turning toward +X requires negative yaw.
            for wheel in front {
                XCTAssertLessThan(wheel.eulerAngles.y, 0)
                let axle = wheel.convertVector(SCNVector3(1, 0, 0), to: vehicle)
                // Up cross axle gives the wheel's forward heading, independently of its spin.
                XCTAssertGreaterThan(axle.z, 0, "Front wheel planes must steer toward the requested +X travel.")
            }
            for wheel in rear { XCTAssertEqual(wheel.eulerAngles.y, 0, accuracy: 0.001) }
            for wheel in wheels {
                XCTAssertTrue(wheel.eulerAngles.x.isFinite)
                XCTAssertTrue(wheel.position.y.isFinite)
                XCTAssertNotEqual(wheel.eulerAngles.x, 0)
            }
            XCTAssertLessThan(suspension.eulerAngles.z, 0, "The body should lean with steering.")
            for frame in 31...60 {
                WorldBuilder.animateVehicle(vehicle, time: Float(frame) / 60, speed: 20, steering: -0.8)
            }
            XCTAssertGreaterThan(suspension.eulerAngles.z, 0, "Body lean should follow a sustained steering reversal.")
            for wheel in front {
                XCTAssertGreaterThan(wheel.eulerAngles.y, 0)
                let axle = wheel.convertVector(SCNVector3(1, 0, 0), to: vehicle)
                XCTAssertLessThan(axle.z, 0, "Reversing steering must turn the wheel planes toward -X travel.")
            }
            for wheel in rear { XCTAssertEqual(wheel.eulerAngles.y, 0, accuracy: 0.001) }
        }
    }

    func testRoadSurfaceIsSeededVariedAndFiniteFarFromSpawn() {
        var seedDifference: Float = 0
        var minimum: Float = .infinity
        var maximum: Float = -.infinity
        for index in 0...120 {
            let distance = Double(index) * 3.7
            for x: Float in [-4.1, 0, 4.1] {
                let first = RoadSurface.sample(distance: distance, x: x, seed: 17)
                let replay = RoadSurface.sample(distance: distance, x: x, seed: 17)
                let alternate = RoadSurface.sample(distance: distance, x: x, seed: 18)
                XCTAssertEqual(first.height, replay.height)
                XCTAssertEqual(first.pitch, replay.pitch)
                XCTAssertEqual(first.roll, replay.roll)
                for value in [first.height, first.pitch, first.roll, first.roughness] { XCTAssertTrue(value.isFinite) }
                XCTAssertGreaterThanOrEqual(first.height, -1.1)
                XCTAssertLessThanOrEqual(first.height, 0.9)
                XCTAssertLessThan(abs(first.pitch), 0.3)
                XCTAssertLessThan(abs(first.roll), 0.3)
                XCTAssertTrue((0...1).contains(first.roughness))
                minimum = min(minimum, first.height)
                maximum = max(maximum, first.height)
                seedDifference += abs(first.height - alternate.height)
            }
        }
        XCTAssertGreaterThan(maximum - minimum, 0.2, "The surface must contain visible hills and depressions.")
        XCTAssertGreaterThan(seedDifference, 1, "Different route seeds should produce different terrain.")
        for distance in [-1e12, 1e12] {
            let sample = RoadSurface.sample(distance: distance, x: 2, seed: 17)
            XCTAssertTrue(sample.height.isFinite)
            XCTAssertTrue(sample.pitch.isFinite)
            XCTAssertTrue(sample.roll.isFinite)
        }
    }

    func testRoadSurfaceStaysContinuousAtChunkBoundaries() {
        for index in -5...30 {
            // A chunk's local -24 edge meets the next chunk's local +24 edge.
            let outgoing = Double(index - 1) * 48 - (-24.0)
            let incoming = Double(index) * 48 - 24.0
            XCTAssertEqual(outgoing, incoming)
            for x: Float in [-5.7, -3.6, 0, 3.6, 5.7] {
                let left = RoadSurface.height(distance: outgoing, x: x, seed: 17)
                let right = RoadSurface.height(distance: incoming, x: x, seed: 17)
                XCTAssertEqual(left, right)
                let before = RoadSurface.height(distance: outgoing - 0.0001, x: x, seed: 17)
                let after = RoadSurface.height(distance: incoming + 0.0001, x: x, seed: 17)
                XCTAssertLessThan(abs(before - after), 0.001, "Crossing a chunk seam must not pop the road height.")
            }
        }
    }

    func testRoadSuspensionSettlesWithoutOvershootAndIsFrameRateIndependent() {
        let target = RoadSample(height: 0.6, pitch: 0.08, roll: -0.06, roughness: 0.5)
        var at60Hz = RoadSuspension()
        var at30Hz = RoadSuspension()
        at60Hz.reset()
        at30Hz.reset()
        let first = at60Hz.update(target, dt: 1.0 / 60)
        XCTAssertGreaterThan(first.height, 0)
        XCTAssertLessThan(first.height, target.height)
        XCTAssertGreaterThan(first.roll, target.roll)
        XCTAssertLessThan(first.roll, 0)
        for _ in 1..<60 { _ = at60Hz.update(target, dt: 1.0 / 60) }
        for _ in 0..<30 { _ = at30Hz.update(target, dt: 1.0 / 30) }
        XCTAssertEqual(at60Hz.state.height, target.height, accuracy: 0.001)
        XCTAssertEqual(at60Hz.state.pitch, at30Hz.state.pitch, accuracy: 0.0001)
        XCTAssertEqual(at60Hz.state.roll, at30Hz.state.roll, accuracy: 0.0001)
        XCTAssertEqual(at60Hz.state.height, at30Hz.state.height, accuracy: 0.0001)
        let beforeFreeze = at60Hz.state
        let frozen = at60Hz.update(.flat, dt: 0)
        XCTAssertEqual(frozen.height, beforeFreeze.height)
        XCTAssertEqual(frozen.pitch, beforeFreeze.pitch)
    }

    func testVisibleRoadMeshMatchesThePhysicalSurface() throws {
        for index in [0, 1, 7] {
            let chunk = WorldBuilder.makeChunk(index: index, seed: 17, night: false)
            let road = try XCTUnwrap(chunk.childNode(withName: "road", recursively: false))
            let vertices = try geometryVertices(road)
            XCTAssertGreaterThan(vertices.count, 50, "The visible road must be a subdivided terrain mesh.")
            for vertex in vertices {
                let distance = Double(index - 1) * 48 - Double(vertex.z)
                let expected = RoadSurface.height(distance: distance, x: vertex.x, seed: 17)
                XCTAssertEqual(vertex.y, expected, accuracy: 0.001,
                               "Wheel physics and rendered asphalt must use the same global surface.")
            }
            let heights = vertices.map(\.y)
            XCTAssertGreaterThan((heights.max() ?? 0) - (heights.min() ?? 0), 0.05)
        }
    }

    func testVisibleRoadAndShoulderMeshesMeetAcrossChunkSeams() throws {
        let first = WorldBuilder.makeChunk(index: 7, seed: 17, night: false)
        let second = WorldBuilder.makeChunk(index: 8, seed: 17, night: false)
        for name in ["road", "terrainShoulder"] {
            func edge(_ chunk: SCNNode, z: Float) throws -> [Int: Float] {
                var heights: [Int: Float] = [:]
                for node in chunk.childNodes where node.name == name {
                    for vertex in try geometryVertices(node) where abs(vertex.z - z) < 0.001 {
                        heights[Int((vertex.x * 1000).rounded())] = vertex.y
                    }
                }
                return heights
            }
            let outgoing = try edge(first, z: -24)
            let incoming = try edge(second, z: 24)
            XCTAssertGreaterThan(outgoing.count, 10)
            XCTAssertEqual(Set(outgoing.keys), Set(incoming.keys))
            for (x, height) in outgoing {
                XCTAssertEqual(height, try XCTUnwrap(incoming[x]), accuracy: 0.001,
                               "Both asphalt and desert shoulders must join without cracks.")
            }
        }
    }

    private func geometryVertices(_ node: SCNNode) throws -> [SCNVector3] {
        let source = try XCTUnwrap(node.geometry?.sources(for: .vertex).first)
        XCTAssertTrue(source.usesFloatComponents)
        XCTAssertEqual(source.bytesPerComponent, 4)
        return source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).map { index in
                let offset = source.dataOffset + index * source.dataStride
                return SCNVector3(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                  bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                  bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
            }
        }
    }

    func testDaylightSkyBlendingReusesBoundedRGBTexturesAndOneLightingMap() throws {
        let scene = SCNScene()
        var skies = Set<ObjectIdentifier>()
        var lightingMaps = Set<ObjectIdentifier>()
        for step in 0...100 {
            WorldBuilder.configureEnvironment(scene: scene, daylight: Float(step) / 100)
            let sky = try XCTUnwrap(scene.background.contents as? UIImage)
            skies.insert(ObjectIdentifier(sky))
            let bitmap = try XCTUnwrap(sky.cgImage)
            XCTAssertEqual(bitmap.bitsPerPixel, 32)
            XCTAssertEqual(bitmap.colorSpace?.model, .rgb)
            let lighting = try XCTUnwrap(scene.lightingEnvironment.contents as? UIImage)
            lightingMaps.insert(ObjectIdentifier(lighting))
        }
        XCTAssertGreaterThan(skies.count, 2)
        XCTAssertLessThanOrEqual(skies.count, 33, "A repeating cycle must reuse a bounded sky palette.")
        XCTAssertEqual(lightingMaps.count, 1, "Changing light level must avoid regenerating image-based lighting maps.")
    }

    func testDayCycleRepeatsThroughSunsetNightAndMorningSmoothly() {
        let day = DayCycle.sample(elapsed: 0)
        let sunset = DayCycle.sample(elapsed: DayCycle.duration * 0.25)
        let night = DayCycle.sample(elapsed: DayCycle.duration * 0.5)
        let morning = DayCycle.sample(elapsed: DayCycle.duration * 0.75)
        XCTAssertEqual(day.phase, .day)
        XCTAssertEqual(sunset.phase, .sunset)
        XCTAssertEqual(night.phase, .night)
        XCTAssertEqual(morning.phase, .morning)
        XCTAssertFalse(day.isNight)
        XCTAssertTrue(night.isNight)
        XCTAssertGreaterThan(day.daylight, night.daylight)
        XCTAssertGreaterThan(sunset.warmth, day.warmth)
        XCTAssertGreaterThan(night.nightLights, day.nightLights)
        let repeated = DayCycle.sample(elapsed: DayCycle.duration)
        XCTAssertEqual(repeated.phase, day.phase)
        XCTAssertEqual(repeated.daylight, day.daylight, accuracy: 0.0001)
        XCTAssertEqual(repeated.sunElevation, day.sunElevation, accuracy: 0.0001)
        XCTAssertEqual(DayCycle.sample(elapsed: -DayCycle.duration * 0.25).phase, .morning)
        XCTAssertEqual(DayCycle.sample(elapsed: 0, offset: DayCycle.duration * 0.5).phase, .night)

        var previous = day
        for step in 1...1200 {
            let current = DayCycle.sample(elapsed: Double(step) * DayCycle.duration / 1200)
            XCTAssertTrue((0...1).contains(current.daylight))
            XCTAssertTrue((0...1).contains(current.nightLights))
            XCTAssertLessThan(abs(current.daylight - previous.daylight), 0.03)
            XCTAssertLessThan(abs(current.nightLights - previous.nightLights), 0.05,
                              "Headlights and lamps should fade rather than switch abruptly.")
            previous = current
        }
    }

    func testDayCycleUsesActiveSimulationTimeAndManualSkipKeepsCycling() {
        let game = GameModel(seed: 17)
        game.start()
        advance(game, from: 0, seconds: 3)
        let progress = game.cycleProgress
        let clock = game.simulationClock
        XCTAssertGreaterThan(progress, 0)
        game.setPaused(true)
        advance(game, from: 3, seconds: 2)
        XCTAssertEqual(game.cycleProgress, progress)
        XCTAssertEqual(game.simulationClock, clock)
        game.setPaused(false)
        advance(game, from: 100, seconds: 0.5)
        XCTAssertGreaterThan(game.cycleProgress, progress)
        XCTAssertLessThan(game.simulationClock - clock, 0.6)
        game.toggleNight()
        XCTAssertTrue(game.isNight)
        let skippedProgress = game.cycleProgress
        advance(game, from: 100.5, seconds: 0.5)
        XCTAssertGreaterThan(game.cycleProgress, skippedProgress,
                             "Skipping to night should preserve the automatic solar cycle.")
    }

    private func readyGunner(seed: UInt64) -> GameModel {
        let game = GameModel(seed: seed)
        game.start()
        game.toggleGunner()
        advance(game, from: 0, seconds: 1.3)
        XCTAssertFalse(game.isTransitioning)
        return game
    }

    private func descendantCount(_ node: SCNNode) -> Int {
        var count = 0
        node.enumerateChildNodes { _, _ in count += 1 }
        return count
    }

    private func advance(_ game: GameModel, from start: TimeInterval, seconds: TimeInterval) {
        game.update(time: start)
        let frames = Int((seconds * 60).rounded())
        for frame in 1...max(1, frames) {
            game.update(time: start + Double(frame) / 60)
        }
    }

    /// Compare the visible layout and active culling bounds, including lazy flattened meshes.
    private func geometrySignature(_ root: SCNNode) -> [Float] {
        var values: [Float] = []
        root.enumerateChildNodes { node, _ in
            values.append(contentsOf: [node.position.x, node.position.y, node.position.z,
                                       node.scale.x, node.scale.y, node.scale.z])
            if node.geometry != nil {
                let bounds = node.boundingBox
                values.append(contentsOf: [bounds.min.x, bounds.min.y, bounds.min.z,
                                           bounds.max.x, bounds.max.y, bounds.max.z])
            }
        }
        return values
    }
}
