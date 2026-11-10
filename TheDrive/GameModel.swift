import Combine
import Metal
import SceneKit
import UIKit

/// Owns simulation state. World geometry is kept near the origin to support endless runs.
@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var distance = 0
    @Published private(set) var score = 0
    @Published private(set) var health = 1.0
    @Published private(set) var isGameOver = false
    @Published private(set) var isCrashing = false
    @Published private(set) var isGunning = false
    @Published private(set) var isNight = false
    @Published private(set) var timeOfDay = "DAY"
    @Published private(set) var cycleProgress = 0.0
    var simulationClock: Double { elapsed }
    @Published private(set) var started = false
    @Published private(set) var isInCutscene = false
    @Published private(set) var openingProgress = 0.0
    @Published private(set) var runCash = 0
    @Published private(set) var magazineCapacity = 24
    let garage: GarageProgress
    @Published private(set) var seed: UInt64 = 1
    @Published private(set) var speed = 72.0
    @Published private(set) var kills = 0
    @Published private(set) var dodges = 0
    @Published private(set) var warning = ""
    @Published private(set) var nearestPursuer = 30.0
    @Published private(set) var isPaused = false
    @Published private(set) var transitionProgress: Float = 0
    @Published private(set) var isTransitioning = false
    @Published private(set) var aimPoint = CGPoint(x: 0.5, y: 0.52)
    @Published private(set) var aimX: Float = 0
    @Published private(set) var aimY: Float = 0.04
    @Published private(set) var ammo = 24
    @Published private(set) var isReloading = false
    @Published private(set) var hitMarker = false
    @Published private(set) var recoil: Float = 0
    private(set) var shotsFired = 0
    private(set) var hits = 0
    var enemyPositions: [SCNVector3] { enemies.map { $0.node.position } }
    var tracerCount: Int { tracers.count }
    private let requestedSeed: UInt64?
    private var aimOrigin = SCNVector3Zero
    private var aimDirection = SCNVector3(0, 0, 1)
    private var hasAimRay = false
    private var reloadClock = 0.0
    private var hitMarkerClock = 0.0
    private var turret: SCNNode?
    private var tracers: [SCNNode] = []
    private var tracerLifetimes: [Double] = []
    private var nextTracer = 0
    private struct Wreck {
        let node: SCNNode
        let vehicle: SCNNode
        let motion: CrashMotion
        let effects: SCNNode
        let emitters: [SCNParticleSystem]
        var age: Float = 0
        var scroll: Float = 0
    }
    private var wrecks: [Wreck] = []
    private var fatalCrash: Wreck?
    private var fatalCrashAge: Float = 0
    var activeWreckCount: Int { wrecks.count }
    var wreckPositions: [SCNVector3] { wrecks.map { $0.node.position } }
    var wreckAngles: [SCNVector3] { wrecks.map { $0.node.eulerAngles } }


    let scene = SCNScene()
    let cameraNode = SCNNode()
    let rearCameraNode = SCNNode()
    let roadCameraNode = SCNNode()
    private var lensMaterials: [SCNMaterial] = []
    private var impactBounce: Float = 0
    private let world = SCNNode()
    private var jeep = SCNNode()
    private let ambient = SCNNode()
    private let sun = SCNNode()
    private var chunks: [SCNNode] = []
    private var nextChunk = 0
    private var nextHazardID = 0
    private var hazards: [Hazard] = []
    private var enemies: [Enemy] = []
    private var random = SeededRandom(state: 1)
    private var steering: Float = 0
    private var targetX: Float = 0
    private var firing = false
    private var lastTime: TimeInterval?
    private var meters: Double = 0
    private var runStartDistance = 0.0
    private var titleClock = 0.0
    private var openingClock = 0.0
    private let openingDuration = 7.0
    private var marketplace: SCNNode?
    private var armorTier = 0
    private var engineTier = 0
    private var drivingVelocity = 20.0
    private var elapsed = 0.0
    private var dayCycleOffset = 0.0
    private var daylight = DayCycle.sample(elapsed: 0)
    private var lightingClock = 0.0
    private var lightingNeedsRefresh = true
    private var windowMaterials: [SCNMaterial] = []
    private var glowMaterials: [SCNMaterial] = []
    private var streetLights: [SCNLight] = []
    private var vehicleLights: [SCNLight] = []
    private var roadSuspension = RoadSuspension()
    private var obstacleClock = 0.0
    private var enemyClock = 0.0
    private var shotClock = 0.0
    private var damageClock = 0.0
    private var hudClock = 0.0
    private var warningClock = 0.0

    private struct Hazard {
        let id: Int
        let node: SCNNode
        let pedestrian: Bool
        let drift: Float
        var passed = false
    }
    private struct Enemy {
        let node: SCNNode
        let kind: Int
        var hitPoints: Int
        var reaction: Double = 0
        var desiredX: Float = 0
        var dodgeClock: Double = 0
        var dodgeOffset: Float = 0
        var impactedHazards: Set<Int> = []
        var suspension = RoadSuspension()
    }

    init(seed: UInt64? = nil, garage: GarageProgress? = nil) {
        requestedSeed = seed
        self.garage = garage ?? GarageProgress(defaults: nil)
        scene.rootNode.addChildNode(world)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 250
        cameraNode.camera?.fieldOfView = 64
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIntensity = 0.12
        cameraNode.camera?.bloomThreshold = 1.4
        cameraNode.camera?.exposureOffset = -0.15
        for camera in [rearCameraNode, roadCameraNode] {
            camera.camera = SCNCamera()
            camera.camera?.zFar = 95
            camera.camera?.fieldOfView = 72
            camera.camera?.projectionDirection = .horizontal
            camera.camera?.categoryBitMask = 1
            scene.rootNode.addChildNode(camera)
        }
        scene.rootNode.addChildNode(cameraNode)
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        scene.rootNode.addChildNode(ambient)
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.light?.maximumShadowDistance = 45
        sun.light?.shadowSampleCount = 4
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.42)
        sun.eulerAngles = SCNVector3(-0.8, -0.5, 0)
        scene.rootNode.addChildNode(sun)
        resetWorld(newSeed: true)
    }

    func start() {
        guard !started else { return }
        let fromOpening = isInCutscene
        runStartDistance = meters
        if !fromOpening {
            jeep.position = SCNVector3(0, RoadSurface.sample(distance: meters, x: 0, seed: seed).height, 0)
            jeep.eulerAngles = SCNVector3Zero
            targetX = 0
        }
        armorTier = garage.level(for: .armor)
        engineTier = garage.level(for: .engine)
        magazineCapacity = 24 + garage.level(for: .magazine) * 4
        ammo = magazineCapacity
        speed = 72 + Double(engineTier * 4)
        drivingVelocity = speed / 3.6
        started = true; isInCutscene = false; openingProgress = 1
        isPaused = false; scene.isPaused = false; lastTime = nil
        steering = 0; firing = false
        // The handover starts from the cinematic camera and settles into the driving view.
        updateCamera(dt: fromOpening ? 0 : 1)
    }

    func beginOpening() {
        guard !started, !isInCutscene, !isGameOver else { return }
        isInCutscene = true; openingProgress = 0; openingClock = 0
        titleClock = 0; meters = 0; runStartDistance = 0
        steering = 0; firing = false; targetX = 0
        jeep.position = SCNVector3(0, RoadSurface.sample(distance: 0, x: 0, seed: seed).height, 0)
        jeep.eulerAngles = SCNVector3Zero
        roadSuspension.reset(to: RoadSurface.sample(distance: 0, x: 0, seed: seed))
        lastTime = nil
        updateOpeningCamera(progress: 0)
    }

    func skipOpening() { if isInCutscene { start() } }
    func restartOpening() { resetWorld(newSeed: true); beginOpening() }
    func setPaused(_ value: Bool) {
        isPaused = value
        scene.isPaused = value
        lastTime = nil
        if value { firing = false; steering = 0 }
    }
    /// The sole secondary renderer feeds both the HUD mirror and the lens material.
    func updateReflectionTexture(_ texture: MTLTexture) {
        guard started, !isPaused, !isGameOver else { return }
        if !isNight {
            for lens in lensMaterials {
                lens.diffuse.contents = texture
                lens.emission.contents = texture
                lens.emission.intensity = 0.22
            }
        }
    }

    func restart() { resetWorld(newSeed: true); start() }
    func steer(_ direction: Int) {
        guard started, !isGameOver, !isCrashing, !isGunning, !isTransitioning, !isPaused else { return }
        targetX = min(4.1, max(-4.1, targetX + Float(direction) * 3.6))
    }
    func setSteering(_ value: Float) {
        steering = started && !isGameOver && !isCrashing && !isPaused && !isGunning && !isTransitioning ? min(1, max(-1, value)) : 0
    }
    func toggleGunner() {
        guard started, !isGameOver, !isCrashing, !isPaused, !isTransitioning else { return }
        isGunning.toggle()
        isTransitioning = true
        hasAimRay = false
        applyLighting()
        steering = 0
        firing = false
    }
    func setFiring(_ value: Bool) {
        firing = value && isGunning && !isTransitioning && started && !isGameOver && !isCrashing && !isPaused
    }
    func setAim(_ point: CGPoint) {
        aimPoint = CGPoint(x: min(0.95, max(0.05, point.x)), y: min(0.92, max(0.08, point.y)))
        aimX = Float(aimPoint.x * 2 - 1)
        aimY = Float(aimPoint.y * 2 - 1)
    }
    func setAim(x: Float, y: Float) { setAim(CGPoint(x: CGFloat(x + 1) / 2, y: CGFloat(y + 1) / 2)) }
    /// Ray comes from SCNView.unprojectPoint at the reticle, in scene coordinates.
    func setAimRay(origin: SCNVector3, direction: SCNVector3) {
        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        guard length > 0.001, length.isFinite, origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else { return }
        aimOrigin = origin
        aimDirection = SCNVector3(direction.x / length, direction.y / length, direction.z / length)
        hasAimRay = true
    }
    func reload() {
        guard started, !isGameOver, !isCrashing, !isPaused, !isReloading, ammo < magazineCapacity else { return }
        isReloading = true
        reloadClock = 1.5
    }
    func toggleNight() {
        dayCycleOffset = (isNight ? 0 : DayCycle.duration / 2) - elapsed
        applyLighting()
    }

    private func resetWorld(newSeed: Bool) {
        world.childNodes.forEach { $0.removeFromParentNode() }
        if newSeed { seed = requestedSeed ?? UInt64.random(in: 1...UInt64.max) }
        random = SeededRandom(state: seed)
        chunks.removeAll(); hazards.removeAll(); enemies.removeAll()
        distance = 0; score = 0; health = 1; kills = 0; dodges = 0
        isGameOver = false; isCrashing = false; fatalCrash = nil; fatalCrashAge = 0; isGunning = false; started = false
        meters = 0; elapsed = 0; obstacleClock = 1.8; enemyClock = 3; drivingVelocity = 20
        runStartDistance = 0; runCash = 0; titleClock = 0; openingClock = 0
        isInCutscene = false; openingProgress = 0; armorTier = 0; engineTier = 0; magazineCapacity = 24
        dayCycleOffset = 0; lightingClock = 0; daylight = DayCycle.sample(elapsed: 0)
        isNight = false; timeOfDay = "DAY"; cycleProgress = 0
        lightingNeedsRefresh = true
        windowMaterials.removeAll(); glowMaterials.removeAll(); streetLights.removeAll(); vehicleLights.removeAll()
        roadSuspension = RoadSuspension()
        shotClock = 0; damageClock = 0; hudClock = 0; warningClock = 0
        lastTime = nil; steering = 0; targetX = 0; firing = false; warning = ""
        isPaused = false; scene.isPaused = false; nearestPursuer = 30; speed = 72
        impactBounce = 0
        transitionProgress = 0; isTransitioning = false
        ammo = 24; isReloading = false; reloadClock = 0
        hitMarker = false; hitMarkerClock = 0; recoil = 0; shotsFired = 0; hits = 0
        aimPoint = CGPoint(x: 0.5, y: 0.52); aimX = 0; aimY = 0.04; hasAimRay = false
        tracers.removeAll(); tracerLifetimes.removeAll(); nextTracer = 0; wrecks.removeAll()
        jeep = WorldBuilder.makeJeep()
        roadSuspension.reset(to: RoadSurface.sample(distance: 0, x: 0, seed: seed))
        jeep.position.y = roadSuspension.state.height
        turret = jeep.childNode(withName: "turret", recursively: true)
        lensMaterials.removeAll()
        jeep.enumerateChildNodes { node, _ in
            if node.name == "sunglassLens", let material = node.geometry?.firstMaterial {
                node.categoryBitMask = 2
                lensMaterials.append(material)
            }
        }
        world.addChildNode(jeep)
        prepareTracerPool()
        nextChunk = 0; nextHazardID = 0
        for index in -1...4 {
            let chunk = WorldBuilder.makeChunk(index: nextChunk, seed: seed, night: isNight, openingMarket: (1...3).contains(nextChunk))
            nextChunk += 1
            chunk.position.z = -Float(index) * 48
            world.addChildNode(chunk)
            chunks.append(chunk)
        }
        for kind in 0...2 { spawnEnemy(kind: kind, z: Float(30 + kind * 10)) }
        marketplace = Marketplace.make(seed: seed)
        if let marketplace { world.addChildNode(marketplace) }
        cameraNode.position = SCNVector3(1.2, 3.8, 7.2)
        cameraNode.look(at: SCNVector3(0, 1, -18))
        updateCamera(dt: 1)
        updateTitlePreview(dt: 0)
        applyLighting()
    }

    private func applyLighting() {
        lightingNeedsRefresh = true
        updateLighting(force: true)
    }

    private func refreshLightingTargets() {
        windowMaterials.removeAll(); glowMaterials.removeAll(); streetLights.removeAll(); vehicleLights.removeAll()
        var seenWindows = Set<ObjectIdentifier>()
        var seenGlows = Set<ObjectIdentifier>()
        world.enumerateChildNodes { node, _ in
            if let material = node.geometry?.firstMaterial {
                if node.name == "litWindow", seenWindows.insert(ObjectIdentifier(material)).inserted {
                    windowMaterials.append(material)
                } else if ["lampGlow", "headlamp"].contains(node.name ?? ""), seenGlows.insert(ObjectIdentifier(material)).inserted {
                    glowMaterials.append(material)
                }
            }
            if let light = node.light {
                if node.name == "streetLight" { streetLights.append(light) }
                if node.name == "headlight" { vehicleLights.append(light) }
            }
        }
        lightingNeedsRefresh = false
    }

    private func updateLighting(force: Bool = false) {
        guard force || lightingClock >= 0.1 || lightingNeedsRefresh else { return }
        lightingClock = 0
        let state = DayCycle.sample(elapsed: elapsed, offset: dayCycleOffset)
        if state.isNight != isNight {
            isNight = state.isNight
            WorldBuilder.setNight(isNight, in: world)
        }
        daylight = state
        if timeOfDay != state.phase.rawValue { timeOfDay = state.phase.rawValue }
        cycleProgress = state.normalizedTime
        if lightingNeedsRefresh { refreshLightingTargets() }
        let light = CGFloat(state.daylight)
        let warm = UIColor(red: 1, green: 0.65, blue: 0.24, alpha: 1)
        let sky = mix(UIColor(red: 0.035, green: 0.055, blue: 0.12, alpha: 1), UIColor(red: 0.77, green: 0.61, blue: 0.43, alpha: 1), light)
        scene.fogColor = mix(sky, UIColor(red: 0.88, green: 0.39, blue: 0.18, alpha: 1), CGFloat(state.warmth) * 0.32)
        ambient.light?.color = mix(UIColor(red: 0.35, green: 0.42, blue: 0.65, alpha: 1), UIColor(red: 0.85, green: 0.76, blue: 0.63, alpha: 1), light)
        ambient.light?.intensity = 380 + CGFloat(state.daylight) * 270
        sun.light?.intensity = 180 + CGFloat(state.daylight) * 920
        sun.light?.color = mix(UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 1), mix(UIColor(red: 1, green: 0.83, blue: 0.63, alpha: 1), UIColor(red: 1, green: 0.48, blue: 0.24, alpha: 1), CGFloat(state.warmth)), light)
        sun.eulerAngles = SCNVector3(-0.25 - max(0.1, state.sunElevation), Float(state.normalizedTime * 2 * .pi) - 0.5, 0)
        sun.light?.castsShadow = state.daylight > 0.2
        WorldBuilder.configureEnvironment(scene: scene, daylight: state.daylight)
        let lamps = CGFloat(state.nightLights)
        for material in windowMaterials {
            material.diffuse.contents = mix(UIColor(red: 0.1, green: 0.13, blue: 0.14, alpha: 1), warm, lamps)
            material.emission.contents = warm
            material.emission.intensity = lamps
        }
        for material in glowMaterials { material.emission.contents = warm; material.emission.intensity = lamps }
        for lamp in streetLights { lamp.intensity = 380 * lamps }
        for lamp in vehicleLights { lamp.intensity = 950 * lamps }
    }

    private func mix(_ first: UIColor, _ second: UIColor, _ amount: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        first.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        second.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = min(1, max(0, amount))
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }

    /// Independent tire travel follows the visible height mesh, beyond the fitted body plane.
    private func applyRoadContacts(to vehicle: SCNNode, distance: Double, pose: RoadSample) {
        for wheel in vehicle.childNodes where wheel.name == "wheel" {
            let ground = RoadSurface.height(distance: distance - Double(wheel.position.z), x: vehicle.position.x + wheel.position.x, seed: seed)
            let plane = pose.height + pose.roll * wheel.position.x - pose.pitch * wheel.position.z
            wheel.position.y += min(0.16, max(-0.16, ground - plane))
        }
    }

    func update(time: TimeInterval) {
        defer { lastTime = time }
        guard let previous = lastTime, !isGameOver, !isPaused else { return }
        let dt = min(max(time - previous, 0), 1.0 / 20)
        guard dt > 0 else { return }
        if !started {
            if isInCutscene { updateOpening(dt: dt) }
            else { updateTitlePreview(dt: dt) }
            return
        }
        elapsed += dt
        lightingClock += dt
        updateLighting()
        updateWeaponTimers(dt: dt)
        if isCrashing {
            updateFatalCrash(dt: Float(dt))
            return
        }
        if isTransitioning {
            let direction: Float = isGunning ? 1 : -1
            transitionProgress = min(1, max(0, transitionProgress + direction * Float(dt / 1.1)))
            if (isGunning && transitionProgress >= 1) || (!isGunning && transitionProgress <= 0) {
                isTransitioning = false
            }
        }
        let pace = DrivingPace.sample(distance: max(0, meters - runStartDistance), seed: seed, engineTier: engineTier)
        drivingVelocity = DrivingPace.filteredVelocity(current: drivingVelocity, target: pace.targetKPH / 3.6, dt: dt)
        let velocity = Float(drivingVelocity)
        let step = velocity * Float(dt)
        meters += Double(step)
        bankDistanceCash()
        damageClock = max(0, damageClock - dt)
        warningClock -= dt
        if warningClock <= 0 { warning = "" }
        if !isGunning && !isTransitioning { targetX = min(4.1, max(-4.1, targetX + steering * Float(dt) * 8)) }
        let oldX = jeep.position.x
        jeep.position.x += (targetX - jeep.position.x) * min(1, Float(dt) * 10)
        impactBounce = max(0, impactBounce - Float(dt) * 1.8)
        let road = roadSuspension.update(RoadSurface.sample(distance: meters, x: jeep.position.x, seed: seed), dt: Float(dt))
        jeep.position.y = road.height
        jeep.eulerAngles.x = road.pitch
        jeep.eulerAngles.z = road.roll + (oldX - jeep.position.x) * 0.4
        WorldBuilder.animateVehicle(jeep, time: Float(elapsed), speed: velocity, impact: impactBounce,
                                    steering: max(-1, min(1, (jeep.position.x - oldX) / max(0.001, Float(dt)) / 8)))
        applyRoadContacts(to: jeep, distance: meters, pose: road)
        jeep.eulerAngles.y = (oldX - jeep.position.x) * 0.12
        WorldBuilder.poseDriver(in: jeep, progress: transitionProgress, time: Float(elapsed))
        updateCamera(dt: Float(dt))
        if transitionProgress > 0.95, hasAimRay {
            let aimEnd = SCNVector3(aimOrigin.x + aimDirection.x * 85, aimOrigin.y + aimDirection.y * 85, aimOrigin.z + aimDirection.z * 85)
            turret?.look(at: aimEnd, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        }

        scrollRoad(by: step)
        updateWrecks(dt: Float(dt), scroll: step)
        obstacleClock -= dt
        if obstacleClock <= 0 {
            spawnHazard()
            obstacleClock = Double.random(in: 1.8...2.8, using: &random)
        }
        enemyClock -= dt
        if enemyClock <= 0, enemies.count < 7 {
            spawnEnemy(kind: Int.random(in: 0...2, using: &random), z: Float.random(in: 38...58, using: &random))
            enemyClock = max(3.5, 7 - elapsed / 100)
        }
        updateHazards(step: step, dt: Float(dt))
        guard !isGameOver, !isCrashing else { return }
        updateEnemies(dt: dt)
        guard !isGameOver, !isCrashing else { return }
        shotClock -= dt
        if firing, !isReloading, !isTransitioning, shotClock <= 0 { shoot(); shotClock = 0.16 }
        hudClock += dt
        if hudClock > 0.1 {
            hudClock = 0
            distance = Int(max(0, meters - runStartDistance))
            speed = Double(velocity) * 3.6
            nearestPursuer = Double(enemies.map { $0.node.position.z }.min() ?? 80)
            score = distance + kills * 150 + dodges * 100
        }
    }

    private func updateTitlePreview(dt: Double) {
        titleClock += dt
        let travel = Float(titleClock.truncatingRemainder(dividingBy: 24)) * 3
        let lane = Float(sin(titleClock * 0.32)) * 0.45
        let road = RoadSurface.sample(distance: Double(travel), x: lane, seed: seed)
        jeep.position = SCNVector3(lane, road.height, -travel)
        jeep.eulerAngles = SCNVector3(road.pitch, 0, road.roll)
        WorldBuilder.animateVehicle(jeep, time: Float(titleClock), speed: 3, impact: 0, steering: 0)
        WorldBuilder.poseDriver(in: jeep, progress: 0, time: Float(titleClock))
        cameraNode.position = SCNVector3(lane + 8.2 + Float(sin(titleClock * 0.15)), road.height + 4.7, 8 - travel)
        cameraNode.look(at: SCNVector3(lane, road.height + 0.8, -5 - travel))
        if let marketplace { Marketplace.animate(in: marketplace, time: Float(titleClock)) }
    }

    private func updateOpening(dt: Double) {
        openingClock += dt
        openingProgress = min(1, openingClock / openingDuration)
        let acceleration = max(0, (openingProgress - 0.55) / 0.45)
        let velocity = Float(8 + 12 * acceleration)
        let step = velocity * Float(dt)
        meters += Double(step)
        let lane = Float(sin(openingClock * 0.6)) * 0.35 * Float(1 - openingProgress)
        let road = roadSuspension.update(RoadSurface.sample(distance: meters, x: lane, seed: seed), dt: Float(dt))
        jeep.position = SCNVector3(lane, road.height, 0)
        jeep.eulerAngles = SCNVector3(road.pitch, 0, road.roll)
        WorldBuilder.animateVehicle(jeep, time: Float(openingClock), speed: velocity, impact: 0, steering: 0)
        applyRoadContacts(to: jeep, distance: meters, pose: road)
        WorldBuilder.poseDriver(in: jeep, progress: 0, time: Float(openingClock))
        scrollRoad(by: step)
        if let marketplace { Marketplace.animate(in: marketplace, time: Float(openingClock)) }
        updateOpeningCamera(progress: openingProgress)
        if openingProgress >= 1 { start() }
    }

    private func updateOpeningCamera(progress: Double) {
        let p = Float(progress * progress * (3 - 2 * progress))
        let road = RoadSurface.height(distance: meters, x: jeep.position.x, seed: seed)
        cameraNode.position = SCNVector3(jeep.position.x + 8.2 * (1 - p) + 1.15 * p,
                                        road + 4.7 * (1 - p) + 3.8 * p,
                                        8 * (1 - p) + 7.2 * p)
        let lookZ: Float = -5 * (1 - p) - 16 * p
        cameraNode.look(at: SCNVector3(jeep.position.x * 0.6,
            RoadSurface.height(distance: meters - Double(lookZ), x: jeep.position.x, seed: seed) + 0.9, lookZ))
    }

    private func bankDistanceCash() {
        let earned = Int(max(0, meters - runStartDistance) / 10)
        guard earned > runCash else { return }
        garage.award(distanceCash: earned - runCash)
        runCash = earned
    }

    private func updateCamera(dt: Float) {
        let shake = sin(Float(elapsed) * 37) * impactBounce * 0.12 + recoil * 0.035
        let p = transitionProgress * transitionProgress * (3 - 2 * transitionProgress)
        let arc = sin(p * .pi)
        let forwardFogStart = max(45 + 40 * Double(daylight.daylight), min(95, drivingVelocity * 2))
        let forwardFogEnd = max(135 + 75 * Double(daylight.daylight), min(225, drivingVelocity * 5.2))
        scene.fogStartDistance = forwardFogStart * Double(1 - p) + 30 * Double(p)
        scene.fogEndDistance = forwardFogEnd * Double(1 - p) + 75 * Double(p)
        let desired = SCNVector3(jeep.position.x + 1.15 + 0.65 * p + arc * 4.2,
                                3.8 - 0.6 * p + jeep.position.y + shake + arc * 1.5,
                                7.2 - 13 * p)
        let blend = min(1, dt * 12)
        cameraNode.position = SCNVector3(cameraNode.position.x + (desired.x - cameraNode.position.x) * blend,
                                        cameraNode.position.y + (desired.y - cameraNode.position.y) * blend,
                                        cameraNode.position.z + (desired.z - cameraNode.position.z) * blend)
        let lookHeight = RoadSurface.height(distance: meters + 16 - Double(p) * 41, x: jeep.position.x, seed: seed)
        cameraNode.look(at: SCNVector3(jeep.position.x * (0.6 - 0.35 * p), lookHeight + 0.9 + p * 0.1, -16 + 41 * p), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rearCameraNode.position = SCNVector3(jeep.position.x, jeep.position.y + 2.7, 2.8)
        rearCameraNode.look(at: SCNVector3(jeep.position.x, RoadSurface.height(distance: meters - 45, x: jeep.position.x, seed: seed) + 1.2, 45))
        roadCameraNode.position = SCNVector3(jeep.position.x, jeep.position.y + 2.6, -2.1)
        roadCameraNode.look(at: SCNVector3(jeep.position.x, RoadSurface.height(distance: meters + 55, x: jeep.position.x, seed: seed) + 0.6, -55))
    }

    private func spawnHazard() {
        let pedestrian = Int.random(in: 0...7, using: &random) == 0
        let node = pedestrian ? WorldBuilder.makePedestrian() : WorldBuilder.makeObstacle(kind: Int.random(in: 0...2, using: &random))
        let side: Float = Bool.random(using: &random) ? 1 : -1
        node.position = SCNVector3(pedestrian ? side * 5.6 : Float(Int.random(in: -1...1, using: &random)) * 3.6,
                                   0, -Float(DrivingPace.hazardLead(velocity: drivingVelocity)))
        node.position.y = RoadSurface.height(distance: meters - Double(node.position.z), x: node.position.x, seed: seed)
        node.name = pedestrian ? "pedestrianHazard" : "roadHazard"
        world.addChildNode(node)
        hazards.append(Hazard(id: nextHazardID, node: node, pedestrian: pedestrian, drift: pedestrian ? -side * 0.9 : 0))
        nextHazardID += 1
    }

    private func spawnEnemy(kind: Int, z: Float) {
        let node = WorldBuilder.makePursuer(kind: kind)
        WorldBuilder.setNight(isNight, in: node)
        node.name = "pursuer"
        node.position = SCNVector3(Float.random(in: -3.8...3.8, using: &random), 0, z)
        node.position.y = RoadSurface.sample(distance: meters - Double(z), x: node.position.x, seed: seed).height
        world.addChildNode(node)
        lightingNeedsRefresh = true
        enemies.append(Enemy(node: node, kind: kind, hitPoints: kind == 0 ? 2 : kind == 1 ? 4 : 7, desiredX: node.position.x))
    }

    private func updateHazards(step: Float, dt: Float) {
        for index in hazards.indices {
            hazards[index].node.position.z += step
            if hazards[index].pedestrian { hazards[index].node.position.x += hazards[index].drift * dt }
            let node = hazards[index].node
            let ground = RoadSurface.sample(distance: meters - Double(node.position.z), x: node.position.x, seed: seed)
            node.position.y = RoadSurface.height(distance: meters - Double(node.position.z), x: node.position.x, seed: seed)
            node.eulerAngles.x = ground.pitch
            node.eulerAngles.z = ground.roll
            if hazards[index].pedestrian {
                node.eulerAngles.y = hazards[index].drift > 0 ? .pi / 2 : -.pi / 2
                WorldBuilder.poseWalker(node, phase: node.position.x * 4.6)
            }
            if !hazards[index].passed, node.position.z > -1.6 {
                hazards[index].passed = true
                let difference = abs(node.position.x - jeep.position.x)
                if difference < (hazards[index].pedestrian ? 1.1 : 1.65) {
                    takeDamage(hazards[index].pedestrian ? 0.2 : 0.3)
                    node.opacity = 0.35
                    for enemy in enemies { enemy.node.position.z -= 3 }
                } else if difference < 3.4 {
                    dodges += 1
                    announce("CLOSE CALL +100")
                }
            }
        }
        hazards.removeAll { hazard in
            if hazard.node.position.z > 80 { hazard.node.removeFromParentNode(); return true }
            return false
        }
    }

    private func updateEnemies(dt: Double) {
        var removed: [Int: CrashCause] = [:]
        for index in enemies.indices {
            var enemy = enemies[index]
            enemy.reaction -= dt
            if enemy.reaction <= 0 {
                enemy.desiredX = jeep.position.x
                enemy.reaction = enemy.kind == 0 ? 0.28 : enemy.kind == 1 ? 0.8 : 1.4
                // Bikes slip around debris; rally cars react sooner than heavy armored trucks.
                if let hazard = hazards.first(where: { $0.node.position.z < enemy.node.position.z && $0.node.position.z > enemy.node.position.z - (enemy.kind == 0 ? 17 : 11) && abs($0.node.position.x - enemy.desiredX) < 1.8 }), enemy.kind != 2 {
                    enemy.desiredX = hazard.node.position.x > 0 ? -3.6 : 3.6
                }
            }
            enemy.dodgeClock -= dt
            if firing && enemy.dodgeClock <= 0 {
                // Evasive moves are real, seeded steering changes; there is no hit-probability roll.
                enemy.dodgeOffset = Float.random(in: -1...1, using: &random) * (enemy.kind == 0 ? 3.4 : enemy.kind == 1 ? 2.3 : 0.8)
                enemy.dodgeClock = enemy.kind == 0 ? 0.65 : enemy.kind == 1 ? 1.1 : 1.8
            } else if !firing {
                enemy.dodgeOffset *= max(0, 1 - Float(dt) * 2)
            }
            let agility: Float = enemy.kind == 0 ? 4.5 : enemy.kind == 1 ? 2 : 1.1
            let destination = min(4.5, max(-4.5, enemy.desiredX + enemy.dodgeOffset))
            let lateralSpeed = (destination - enemy.node.position.x) * agility
            enemy.node.position.x += lateralSpeed * Float(dt)
            // A fast evasive lunge into the broken shoulder can overturn a pursuer.
            let shoulderThreshold: Float = enemy.kind == 0 ? 0.8 : enemy.kind == 1 ? 0.35 : 0.2
            if abs(enemy.node.position.x) > 4.2 && enemy.node.position.x * lateralSpeed > 0 && abs(lateralSpeed) > shoulderThreshold {
                removed[index] = .shoulder
                dodges += 1
                announce("SHOULDER ROLLOVER +100")
            }
            let closingSpeed: Float = enemy.kind == 0 ? 1.3 : enemy.kind == 1 ? 1.05 : 0.8
            enemy.node.position.z -= Float(dt) * closingSpeed
            let roadDistance = meters - Double(enemy.node.position.z)
            let ground = enemy.suspension.update(RoadSurface.sample(distance: roadDistance, x: enemy.node.position.x, seed: seed), dt: Float(dt))
            enemy.node.position.y = ground.height
            enemy.node.eulerAngles.x = ground.pitch
            enemy.node.eulerAngles.z = ground.roll + (enemy.kind == 0 ? sin(Float(elapsed) * 4 + Float(index)) * 0.1 : 0)
            for hazard in hazards where abs(hazard.node.position.z - enemy.node.position.z) < 1.5 && abs(hazard.node.position.x - enemy.node.position.x) < (enemy.kind == 0 ? 0.85 : 1.6) {
                if !hazard.pedestrian && !enemy.impactedHazards.contains(hazard.id) {
                    enemy.impactedHazards.insert(hazard.id)
                    if enemy.kind == 2 { enemy.node.position.z += 7; enemy.hitPoints -= 2 }
                    else { removed[index] = .roadblock; dodges += 1; announce("PURSUER WRECKED +100") }
                }
            }
            if enemy.hitPoints <= 0 { removed[index] = .roadblock }
            if removed[index] == nil, enemy.node.position.z < 3.1 { endRun(); return }
            WorldBuilder.animateVehicle(enemy.node, time: Float(elapsed) + Float(index), speed: Float(drivingVelocity) + closingSpeed, impact: 0,
                                        steering: max(-1, min(1, lateralSpeed / 8)))
            applyRoadContacts(to: enemy.node, distance: roadDistance, pose: ground)
            enemies[index] = enemy
        }
        for index in removed.keys.sorted(by: >) {
            wreck(enemies[index].node, kind: enemies[index].kind, cause: removed[index] ?? .roadblock)
            enemies.remove(at: index)
        }
    }

    private func prepareTracerPool() {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 1, green: 0.86, blue: 0.42, alpha: 1)
        material.emission.contents = UIColor.orange
        for _ in 0..<12 {
            let geometry = SCNCylinder(radius: 0.018, height: 1)
            geometry.radialSegmentCount = 4
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.isHidden = true
            node.castsShadow = false
            world.addChildNode(node)
            tracers.append(node)
            tracerLifetimes.append(0)
        }
    }

    private func updateWeaponTimers(dt: Double) {
        if recoil > 0 { recoil = max(0, recoil - Float(dt) * 8) }
        if isReloading {
            reloadClock -= dt
            if reloadClock <= 0 { ammo = magazineCapacity; isReloading = false }
        }
        if hitMarker {
            hitMarkerClock -= dt
            if hitMarkerClock <= 0 { hitMarker = false }
        }
        for index in tracers.indices where tracerLifetimes[index] > 0 {
            tracerLifetimes[index] -= dt
            if tracerLifetimes[index] <= 0 { tracers[index].isHidden = true }
        }
    }

    private func shoot() {
        guard ammo > 0 else { reload(); return }
        guard hasAimRay else { return }
        ammo -= 1
        shotsFired += 1
        recoil = 1
        let origin = aimOrigin
        let direction = aimDirection
        var closest: (index: Int, distance: Float)?
        // Analytic ray/sphere tests keep hits independent of rendering and frame rate.
        for index in enemies.indices {
            let enemy = enemies[index]
            let center = SCNVector3(enemy.node.position.x, enemy.node.position.y + (enemy.kind == 0 ? 1.0 : 1.1), enemy.node.position.z)
            let delta = SCNVector3(center.x - origin.x, center.y - origin.y, center.z - origin.z)
            let along = delta.x * direction.x + delta.y * direction.y + delta.z * direction.z
            guard along > 0, along < 85 else { continue }
            let radius: Float = enemy.kind == 0 ? 0.65 : enemy.kind == 1 ? 1.1 : 1.3
            let perpendicularSquared = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z - along * along
            guard perpendicularSquared <= radius * radius else { continue }
            let entry = along - sqrt(max(0, radius * radius - perpendicularSquared))
            if closest == nil || entry < closest!.distance { closest = (index, entry) }
        }
        let range = closest?.distance ?? 85
        let end = SCNVector3(origin.x + direction.x * range, origin.y + direction.y * range, origin.z + direction.z * range)
        let start = turret?.convertPosition(SCNVector3(0, 1.1, 1.7), to: world) ?? SCNVector3(jeep.position.x, 2, 1)
        let dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let tracer = tracers[nextTracer]
        tracer.position = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2)
        tracer.scale = SCNVector3(1, length, 1)
        tracer.look(at: end, up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 1, 0))
        tracer.isHidden = false
        tracerLifetimes[nextTracer] = 0.065
        nextTracer = (nextTracer + 1) % tracers.count
        if let hit = closest {
            hits += 1
            hitMarker = true
            hitMarkerClock = 0.13
            enemies[hit.index].hitPoints -= 1
            if enemies[hit.index].hitPoints <= 0 {
                wreck(enemies[hit.index].node, kind: enemies[hit.index].kind, cause: .shot)
                enemies.remove(at: hit.index)
                kills += 1
                announce("PURSUER DISABLED +150")
            }
        }
        // The next round rises a little unless the player pulls the reticle down.
        setAim(CGPoint(x: aimPoint.x, y: aimPoint.y - 0.003))
        if ammo == 0 { reload() }
    }

    private func scrollRoad(by step: Float) {
        if let marketplace {
            marketplace.position.z += step
            if marketplace.position.z > 140 {
                marketplace.removeFromParentNode()
                self.marketplace = nil
            }
        }
        for chunk in chunks { chunk.position.z += step }
        for index in chunks.indices {
            if chunks[index].position.z > 80 {
                let z = (chunks.map { $0.position.z }.min() ?? -144) - 48
                chunks[index].removeFromParentNode()
                let replacement = WorldBuilder.makeChunk(index: nextChunk, seed: seed, night: isNight)
                nextChunk += 1
                replacement.position.z = z
                world.addChildNode(replacement)
                chunks[index] = replacement
                lightingNeedsRefresh = true
            }
        }
    }

    private func makeWreck(_ vehicle: SCNNode, kind: Int, cause: CrashCause) -> Wreck {
        let original = vehicle.position
        let wrapper = SCNNode()
        wrapper.name = "crashMotion"
        wrapper.position = SCNVector3(original.x, original.y + 0.85, original.z)
        world.addChildNode(wrapper)
        vehicle.removeFromParentNode()
        vehicle.removeAllActions()
        vehicle.position = SCNVector3(0, -0.85, 0)
        vehicle.eulerAngles = SCNVector3Zero
        wrapper.addChildNode(vehicle)
        let effects = WorldBuilder.makeCrashEffects()
        effects.position = original
        world.addChildNode(effects)
        var emitters = effects.particleSystems ?? []
        effects.enumerateChildNodes { node, _ in emitters.append(contentsOf: node.particleSystems ?? []) }
        return Wreck(node: wrapper, vehicle: vehicle,
                     motion: CrashMotion(start: original, kind: kind, side: original.x >= 0 ? 1 : -1, cause: cause), effects: effects, emitters: emitters)
    }

    private func wreck(_ node: SCNNode, kind: Int, cause: CrashCause) {
        if wrecks.count >= 8 {
            let oldest = wrecks.removeFirst()
            oldest.node.removeFromParentNode()
            oldest.effects.removeFromParentNode()
        }
        wrecks.append(makeWreck(node, kind: kind, cause: cause))
    }

    private func updateWrecks(dt: Float, scroll: Float) {
        for index in wrecks.indices {
            wrecks[index].age += dt
            wrecks[index].scroll += scroll
            applyWreckPose(&wrecks[index])
        }
        wrecks.removeAll { wreck in
            guard wreck.age >= 3.2 else { return false }
            wreck.node.removeFromParentNode()
            wreck.effects.removeFromParentNode()
            return true
        }
    }

    private func applyWreckPose(_ wreck: inout Wreck) {
        let pose = wreck.motion.sample(age: wreck.age)
        let z = pose.position.z + wreck.scroll
        let terrain = RoadSurface.height(distance: meters - Double(z), x: pose.position.x, seed: seed)
        wreck.node.position = SCNVector3(pose.position.x, terrain + pose.position.y - wreck.motion.start.y, z)
        wreck.node.eulerAngles = pose.angles
        wreck.node.opacity = CGFloat(min(1, max(0, (3.2 - wreck.age) / 0.5)))
        wreck.effects.position = SCNVector3(wreck.node.position.x, terrain + 0.15, wreck.node.position.z)
        // Emission follows simulation time and therefore stops at pause just like the car.
        if wreck.age >= 2.4 { for system in wreck.emitters { system.birthRate = 0 } }
    }

    private func beginFatalCrash() {
        guard !isCrashing else { return }
        isCrashing = true
        firing = false; steering = 0; isTransitioning = false
        fatalCrash = makeWreck(jeep, kind: 1, cause: .roadblock)
        fatalCrashAge = 0
        announce("JEEP OVERTURNED")
    }

    private func updateFatalCrash(dt: Float) {
        fatalCrashAge += dt
        let deceleration = max(0, 1 - fatalCrashAge / 1.4)
        let step = Float(drivingVelocity) * deceleration * dt
        meters += Double(step)
        scrollRoad(by: step)
        updateWrecks(dt: dt, scroll: step)
        for hazard in hazards { hazard.node.position.z += step }
        for enemy in enemies { enemy.node.position.z += step }
        if var crash = fatalCrash {
            crash.age = min(3.0, fatalCrashAge * (3.0 / 1.4))
            applyWreckPose(&crash)
            fatalCrash = crash
            let target = crash.node.position
            let desired = SCNVector3(target.x + 6, 5.5, target.z + 9)
            let blend = min(1, dt * 3)
            cameraNode.position = SCNVector3(cameraNode.position.x + (desired.x - cameraNode.position.x) * blend,
                                            cameraNode.position.y + (desired.y - cameraNode.position.y) * blend,
                                            cameraNode.position.z + (desired.z - cameraNode.position.z) * blend)
            cameraNode.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }
        if fatalCrashAge >= 1.4 { isCrashing = false; endRun() }
    }

    private func takeDamage(_ amount: Double) {
        guard damageClock <= 0 else { return }
        health = max(0, health - amount * (1 - Double(armorTier) * 0.15))
        impactBounce = 1
        damageClock = 0.9
        announce("IMPACT — PURSUERS CLOSING")
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        if health <= 0 { beginFatalCrash() }
    }
    private func announce(_ text: String) { warning = text; warningClock = 1.8 }
    private func endRun() {
        isGameOver = true; firing = false; steering = 0
        bankDistanceCash()
        distance = Int(max(0, meters - runStartDistance)); score = distance + kills * 150 + dodges * 100
    }
}

private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}


/// Arcade rollover pose sampled from elapsed simulation time, independent of SceneKit actions.
enum CrashCause { case shot, roadblock, shoulder }

struct CrashPose {
    let position: SCNVector3
    let angles: SCNVector3
    let isLanded: Bool
}

struct CrashMotion {
    let start: SCNVector3
    let kind: Int
    let side: Float
    let cause: CrashCause

    func sample(age: Float) -> CrashPose {
        let time = max(0, age)
        let flightDuration: Float = kind == 0 ? 1.25 : 1.55
        let flight = min(1, time / flightDuration)
        let eased = 1 - pow(1 - flight, 2)
        let roll: Float
        let pitch: Float
        if kind == 0 {
            roll = side * .pi * 2 * eased
            pitch = -.pi * 4 * eased
        } else if cause == .roadblock {
            roll = side * .pi * 3 * eased
            pitch = -.pi * 2 * eased
        } else {
            roll = side * .pi * 3 * eased
            pitch = -.pi * 0.45 * sin(flight * .pi)
        }
        let landedTime = max(0, time - flightDuration)
        let bounce = landedTime < 0.65 ? abs(sin(landedTime * 11)) * exp(-landedTime * 5) * 0.48 : 0
        let height = sin(flight * .pi) * (kind == 0 ? 2.6 : 3.5) + bounce
        // Conservative rotated-body support keeps wheels/body above gravel during the roll.
        let support = abs(sin(roll)) * (kind == 0 ? 0.5 : 1.2) + abs(cos(roll)) * 0.85 + abs(sin(pitch)) * (kind == 0 ? 1.0 : 1.75)
        let centerHeight = max(0.85 + height, support + 0.03)
        let slide = min(1, landedTime / 1.4)
        let sideways = side * ((cause == .shoulder ? 3.3 : 2.2) * flight + slide * 1.8)
        // Keep the slide on the broken shoulder, before the town's building fronts.
        let lateralTravel: Float = cause == .shoulder ? 5.1 : 4
        let clearance = max(0, 6.6 - side * start.x)
        let travelScale = min(1, clearance / lateralTravel)
        return CrashPose(position: SCNVector3(start.x + sideways * travelScale, start.y + centerHeight, start.z + flight * 5 + slide * 4),
                         angles: SCNVector3(pitch, side * 0.6 * eased, roll), isLanded: flight >= 1)
    }
}
