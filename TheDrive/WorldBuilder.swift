import SceneKit
import UIKit
import simd

/// Asset-free scenery: each 48 m block is reproducible from its seed and index.
@MainActor
enum WorldBuilder {
    static let chunkLength: Float = 48
    private static var textureCache: [String: UIImage] = [:]
    private static let sand = UIColor(red: 0.66, green: 0.45, blue: 0.28, alpha: 1)
    private static let dark = UIColor(red: 0.10, green: 0.13, blue: 0.14, alpha: 1)
    private static let rust = UIColor(red: 0.48, green: 0.23, blue: 0.14, alpha: 1)
    private static let warm = UIColor(red: 1, green: 0.65, blue: 0.24, alpha: 1)

    static func makeChunk(index: Int, seed: UInt64, night: Bool, openingMarket: Bool = false) -> SCNNode {
        var rng = SeededRandom(state: seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15)
        let root = SCNNode()
        let centerDistance = Double(index - 1) * Double(chunkLength)
        func roadHeight(_ x: Float, _ z: Float) -> Float {
            RoadSurface.height(distance: centerDistance - Double(z), x: x, seed: seed)
        }
        // A deep base closes the far horizon; the visible sand and asphalt are actual meshes.
        let ground = box(80, 0.2, 48, sand, at: SCNVector3(0, -2, 0))
        ground.name = "ground"
        ground.geometry?.firstMaterial = surface("sand", tint: sand, repeatX: 10, repeatY: 6)
        root.addChildNode(ground)
        let road = groundMesh(x: -5.7...5.7, z: -24...24, columns: 12, rows: 48,
                              material: surface("asphalt", tint: UIColor(white: 0.38, alpha: 1), repeatX: 3, repeatY: 12), height: roadHeight)
        road.name = "road"
        root.addChildNode(road)
        // Four-block districts change density without breaking the continuous seeded road.
        let district = index < 5 ? 0 : abs(index / 4 + Int(seed % 7)) % 4
        let houseRows = district == 0 ? 4 : district == 1 ? 3 : district == 2 ? 2 : 0
        for side: Float in [-1, 1] {
            let range: ClosedRange<Float> = side < 0 ? -40 ... -5.7 : 5.7 ... 40
            let terrain = groundMesh(x: range, z: -24...24, columns: 12, rows: 24,
                                     material: surface("sand", tint: sand, repeatX: 8, repeatY: 6)) { x, z in
                let edge = roadHeight(side * 5.7, z)
                let rise = max(0, abs(x) - 13) * 0.025
                return edge - 0.035 + rise + Float(sin((centerDistance - Double(z)) * 0.08 + Double(x) * 0.17)) * min(0.22, max(0, abs(x) - 8) * 0.02)
            }
            terrain.name = "terrainShoulder"
            root.addChildNode(terrain)
            let lineX = side * 5.35
            root.addChildNode(groundMesh(x: (lineX - 0.065)...(lineX + 0.065), z: -24...24, columns: 1, rows: 48,
                                         material: material(UIColor(red: 0.75, green: 0.62, blue: 0.40, alpha: 1))) { x, z in roadHeight(x, z) + 0.014 })
            for segment in 0..<12 where (segment + index) % 5 != 0 {
                let z = Float(segment) * 4 - 22
                let curb = box(0.3, 0.2, 3.4, sand, at: SCNVector3(side * 5.72, roadHeight(side * 5.7, z) + 0.045, z))
                curb.eulerAngles.x = RoadSurface.sample(distance: centerDistance - Double(z), x: side * 5.7, seed: seed).pitch
                root.addChildNode(curb)
            }
            if houseRows > 0 {
                let wall = box(0.28, 1.05, 42, sand, at: SCNVector3(side * 16.3, roadHeight(side * 5.7, 0) + 0.5, 0))
                wall.geometry?.firstMaterial = surface("masonry", tint: UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 1), repeatX: 2, repeatY: 1)
                root.addChildNode(wall)
            }
            for row in 0..<houseRows {
                let z = houseRows == 4 ? Float(row) * 12 - 18 : Float(row) * 16 - 16
                let ruined = district == 1 || (row + index) % 7 == 0
                placeLot(side: side, z: z, street: openingMarket ? 11.1 : 8.1, model: Int(rng.range(0, 5.999)), ruined: ruined, rng: &rng, roadHeight: roadHeight, into: root)
                placeDesertHome(side: side, z: z, street: 21.2, model: (row + index) % 4, roadHeight: roadHeight, into: root)
                for _ in 0..<(openingMarket ? 0 : (ruined ? 5 : 2)) {
                    let x = side * rng.range(6.4, 8)
                    let rz = z + rng.range(-4, 4)
                    let rock = terrainRock(radius: rng.range(0.18, 0.42))
                    rock.position = SCNVector3(x, roadHeight(side * 5.7, rz) + 0.02, rz)
                    root.addChildNode(rock)
                }
                if row % 2 == 0 && !openingMarket {
                    let drum = makeBarrel()
                    drum.position = SCNVector3(side * 7.25, roadHeight(side * 5.7, z - 3), z - 3)
                    root.addChildNode(drum)
                }
            }
            for row in 0..<4 {
                let z = Float(row) * 12 - 18
                let dune = ellipsoid(radius: rng.range(6, 10), scale: SCNVector3(1.5, district == 3 ? 0.85 : 0.35, 1),
                                     color: UIColor(red: 0.60, green: 0.40, blue: 0.25, alpha: 1),
                                     at: SCNVector3(side * rng.range(40, 52), roadHeight(side * 5.7, z) - 1.5, z))
                root.addChildNode(dune)
                if district != 0 {
                    root.addChildNode(cactus(at: SCNVector3(side * rng.range(9, 17), roadHeight(side * 5.7, z), z)))
                }
            }
            if district != 3 {
                let base = roadHeight(side * 5.7, 4)
                root.addChildNode(cylinder(radius: 0.09, height: 6.5, color: dark, at: SCNVector3(side * 6.8, base + 3.25, 4)))
                root.addChildNode(box(1.5, 0.12, 0.12, dark, at: SCNVector3(side * 6.3, base + 6.3, 4)))
                let lamp = box(0.5, 0.12, 0.6, warm, at: SCNVector3(side * 5.7, base + 6.2, 4))
                lamp.name = "lampGlow"
                lamp.geometry?.firstMaterial = lamp.geometry?.firstMaterial?.copy() as? SCNMaterial
                root.addChildNode(lamp)
                let pool = SCNNode()
                pool.name = "streetLight"
                pool.light = SCNLight()
                pool.light?.type = .omni
                pool.light?.color = warm
                pool.light?.attenuationStartDistance = 1
                pool.light?.attenuationEndDistance = 12
                pool.position = SCNVector3(side * 5.7, base + 5, 4)
                root.addChildNode(pool)
            }
        }
        for centerZ in stride(from: Float(-21), through: 21, by: 7) {
            root.addChildNode(groundMesh(x: -0.06...0.06, z: (centerZ - 1.4)...(centerZ + 1.4), columns: 1, rows: 6,
                                         material: material(UIColor(red: 0.72, green: 0.61, blue: 0.41, alpha: 1))) { x, z in roadHeight(x, z) + 0.014 })
        }
        var dynamic: [SCNNode] = []
        root.enumerateChildNodes { node, _ in
            if ["litWindow", "lampGlow", "streetLight"].contains(node.name ?? "") { dynamic.append(node) }
        }
        for node in dynamic {
            let transform = root.simdWorldTransform.inverse * node.simdWorldTransform
            node.removeFromParentNode()
            root.addChildNode(node)
            node.simdTransform = transform
        }
        for name in ["litWindow", "lampGlow"] {
            let group = SCNNode()
            let matches = root.childNodes.filter { $0.name == name }
            let shared = matches.first?.geometry?.firstMaterial
            for node in matches {
                node.geometry?.firstMaterial = shared
                node.removeFromParentNode(); group.addChildNode(node)
            }
            if !matches.isEmpty {
                let bounds = group.boundingBox
                let mesh = group.flattenedClone()
                mesh.name = name; mesh.boundingBox = bounds
                root.addChildNode(mesh)
            }
        }
        batchStaticChildren(in: root, excluding: ["ground", "road", "importedBuilding", "importedEnvironment", "terrainShoulder", "litWindow", "lampGlow", "streetLight"])
        setNight(night, in: root)
        return root
    }

    static func makeJeep() -> SCNNode {
        if let sculpted = SculptedMesh.load("JeepBody") { return assembledJeep(sculpted) }
        let root = vehicleBody(color: UIColor(red: 0.35, green: 0.40, blue: 0.23, alpha: 1), armored: false)
        root.addChildNode(box(1.75, 0.45, 1.1, UIColor(red: 0.39, green: 0.42, blue: 0.26, alpha: 1), at: SCNVector3(0, 1.05, -0.85)))
        for x: Float in [-0.82, 0.82] {
            root.addChildNode(box(0.09, 1.15, 0.1, dark, at: SCNVector3(x, 1.7, -0.22)))
            root.addChildNode(box(0.1, 1.0, 0.1, dark, at: SCNVector3(x, 1.6, 0.75)))
        }
        root.addChildNode(box(1.75, 0.1, 0.1, dark, at: SCNVector3(0, 2.26, -0.22)))
        root.addChildNode(box(1.75, 0.1, 0.1, dark, at: SCNVector3(0, 2.1, 0.75)))
        root.addChildNode(foldedWindshield())
        for x: Float in [-0.45, 0.45] { root.addChildNode(box(0.5, 0.65, 0.3, dark, at: SCNVector3(x, 1.35, 0.1))) }
        let driver = makeCharacter(skin: UIColor(red: 0.55, green: 0.34, blue: 0.22, alpha: 1), shirt: UIColor(red: 0.23, green: 0.46, blue: 0.51, alpha: 1))
        driver.name = "playerDriver"
        driver.position = SCNVector3(0.45, 1.5, -0.02)
        root.addChildNode(driver)
        root.addChildNode(gunTurret())
        // Rear spare tire.
        let spare = cylinder(radius: 0.43, height: 0.25, color: dark, at: SCNVector3(0, 1.1, 1.65))
        spare.eulerAngles.x = .pi / 2
        root.addChildNode(spare)
        addJeepDetails(to: root)
        installSuspension(on: root, dustRate: 18)
        return root
    }

    /// Surfaced body, with the same wheels, lights, driver and gun as the box fallback.
    private static func assembledJeep(_ body: SCNNode) -> SCNNode {
        let root = vehicleBody(color: UIColor(red: 0.35, green: 0.40, blue: 0.23, alpha: 1), armored: false, chassis: false)
        body.name = "sculptedBody"
        if let paint = body.geometry?.firstMaterial {
            paint.lightingModel = .physicallyBased
            paint.metalness.contents = 0.62
            paint.roughness.contents = texture("gloss")
            paint.clearCoat.contents = 1
            paint.clearCoatRoughness.contents = 0.045
        }
        root.addChildNode(body)
        root.addChildNode(foldedWindshield())
        let driver = makeCharacter(skin: UIColor(red: 0.55, green: 0.34, blue: 0.22, alpha: 1), shirt: UIColor(red: 0.23, green: 0.46, blue: 0.51, alpha: 1))
        driver.name = "playerDriver"
        driver.position = SCNVector3(0.42, 1.08, -0.08)
        root.addChildNode(driver)
        root.addChildNode(gunTurret())
        attachSunglasses(to: root)
        installSuspension(on: root, dustRate: 18)
        return root
    }

    private static func foldedWindshield() -> SCNNode {
        // Folded safari glass keeps the driver's face and glasses visible from the gun camera.
        let windshield = box(1.5, 0.32, 0.04, UIColor(red: 0.55, green: 0.68, blue: 0.70, alpha: 0.15), at: SCNVector3(0, 1.48, -0.42))
        windshield.eulerAngles.x = -0.65
        return windshield
    }

    private static func gunTurret() -> SCNNode {
        let turret = SCNNode()
        turret.name = "turret"
        turret.position = SCNVector3(0, 1.1, 0.85)
        let steel = gunMetal
        let wood = gunWood
        func alongZ(_ node: SCNNode) -> SCNNode {
            node.eulerAngles.x = .pi / 2
            return node
        }
        let assembly = SCNNode()
        let mount = cylinder(radius: 0.09, height: 0.7, color: dark, at: SCNVector3(0, 0.35, 0))
        (mount.geometry as? SCNCylinder)?.radialSegmentCount = 16
        assembly.addChildNode(finished(mount, steel))
        let receiver = box(0.16, 0.14, 0.62, dark, at: SCNVector3(0, 1.02, 0.12))
        (receiver.geometry as? SCNBox)?.chamferRadius = 0.012
        assembly.addChildNode(finished(receiver, steel))
        assembly.addChildNode(finished(box(0.1, 0.035, 0.5, dark, at: SCNVector3(0, 1.11, 0.12)), steel))
        let shroud = alongZ(cylinder(radius: 0.055, height: 0.72, color: dark, at: SCNVector3(0, 1.05, 0.78)))
        (shroud.geometry as? SCNCylinder)?.radialSegmentCount = 18
        assembly.addChildNode(finished(shroud, steel))
        let barrel = alongZ(cylinder(radius: 0.028, height: 1.15, color: dark, at: SCNVector3(0, 1.05, 0.72)))
        (barrel.geometry as? SCNCylinder)?.radialSegmentCount = 16
        assembly.addChildNode(finished(barrel, steel))
        let brake = alongZ(cylinder(radius: 0.048, height: 0.12, color: dark, at: SCNVector3(0, 1.05, 1.32)))
        (brake.geometry as? SCNCylinder)?.radialSegmentCount = 16
        assembly.addChildNode(finished(brake, steel))
        assembly.addChildNode(finished(box(0.012, 0.07, 0.02, dark, at: SCNVector3(0, 1.12, 1.22)), steel))
        assembly.addChildNode(finished(box(0.05, 0.04, 0.02, dark, at: SCNVector3(0, 1.14, -0.12)), steel))
        for side: Float in [-1, 1] {
            assembly.addChildNode(finished(box(0.025, 0.1, 0.16, dark, at: SCNVector3(side * 0.07, 0.94, -0.16)), wood))
        }
        assembly.addChildNode(finished(box(0.18, 0.12, 0.26, rust, at: SCNVector3(0.16, 0.96, 0.02)), steel))
        let flat = assembly.flattenedClone()
        flat.name = "gunAssembly"
        turret.addChildNode(flat)
        return turret
    }

    static func makePursuer(kind: Int) -> SCNNode {
        if kind == 0, let bike = importedBike() { return bike }
        if kind != 0, let imported = importedPursuer(kind: kind) { return imported }
        if kind == 0 {
            let root = SCNNode()
            for z: Float in [-0.8, 0.8] {
                let wheel = detailedWheel(radius: 0.43)
                wheel.position = SCNVector3(0, 0.43, z)
                wheel.scale.x = 0.65
                wheel.name = "wheel"
                root.addChildNode(wheel)
            }
            root.addChildNode(box(0.42, 0.4, 1.2, rust, at: SCNVector3(0, 0.8, 0)))
            root.addChildNode(box(0.7, 0.08, 0.1, dark, at: SCNVector3(0, 1.2, -0.65)))
            let rider = makeCharacter(skin: UIColor(red: 0.62, green: 0.40, blue: 0.27, alpha: 1), shirt: rust, character: .explorer)
            rider.name = "pursuerRider"
            rider.position = SCNVector3(0, 1.35, 0.1)
            root.addChildNode(rider)
            let headlamp = box(0.2, 0.2, 0.08, warm, at: SCNVector3(0, 1.05, -0.85))
            headlamp.name = "headlamp"
            headlamp.geometry?.firstMaterial = headlamp.geometry?.firstMaterial?.copy() as? SCNMaterial
            root.addChildNode(headlamp)
            let light = SCNNode()
            light.name = "headlight"
            light.light = SCNLight()
            light.light?.type = .spot
            light.light?.color = warm
            light.light?.spotInnerAngle = 18
            light.light?.spotOuterAngle = 38
            light.light?.attenuationEndDistance = 30
            light.light?.intensity = 0
            light.position = SCNVector3(0, 1.05, -0.95)
            light.eulerAngles.x = -0.13
            root.addChildNode(light)
            root.addChildNode(box(0.15, 0.2, 0.85, UIColor(white: 0.48, alpha: 1), at: SCNVector3(0.28, 0.5, 0.3)))
            for x: Float in [-0.18, 0.18] {
                let fork = cylinder(radius: 0.035, height: 0.68, color: UIColor(white: 0.65, alpha: 1), at: SCNVector3(x, 0.8, -0.7))
                fork.eulerAngles.x = -0.25
                root.addChildNode(fork)
            }
            installSuspension(on: root, dustRate: 7)
            return root
        }
        let color = kind == 1 ? UIColor(red: 0.72, green: 0.27, blue: 0.15, alpha: 1) : UIColor(red: 0.24, green: 0.29, blue: 0.31, alpha: 1)
        let root = vehicleBody(color: color, armored: kind == 2)
        root.addChildNode(box(1.55, 0.12, 1.65, color, at: SCNVector3(0, 1.9, 0.1)))
        root.addChildNode(box(1.55, 0.65, 0.12, color, at: SCNVector3(0, 1.5, 0.86)))
        for x: Float in [-0.72, 0.72] {
            root.addChildNode(box(0.12, 0.75, 0.12, color, at: SCNVector3(x, 1.5, -0.68)))
        }
        root.addChildNode(box(1.3, 0.55, 0.04, UIColor(red: 0.36, green: 0.48, blue: 0.52, alpha: 0.16), at: SCNVector3(0, 1.53, -0.75)))
        let driver = makeCharacter(skin: kind == 1 ? UIColor(red: 0.48, green: 0.29, blue: 0.18, alpha: 1) : UIColor(red: 0.67, green: 0.44, blue: 0.29, alpha: 1), shirt: rust, character: kind == 1 ? .driver : .grandpa)
        driver.name = "pursuerDriver"
        driver.position = SCNVector3(0.4, 1.23, -0.25)
        root.addChildNode(driver)
        if kind == 1 {
            root.addChildNode(box(0.3, 0.025, 2.8, UIColor(red: 0.89, green: 0.81, blue: 0.61, alpha: 1), at: SCNVector3(0, 1.97, 0)))
            root.addChildNode(box(2.2, 0.12, 0.4, dark, at: SCNVector3(0, 1.55, 1.35)))
        } else {
            root.addChildNode(box(2.3, 0.35, 0.25, dark, at: SCNVector3(0, 0.8, -1.7)))
            for x: Float in [-0.6, 0, 0.6] { root.addChildNode(box(0.1, 0.5, 0.15, dark, at: SCNVector3(x, 1.4, -0.82))) }
        }
        addCarDetails(to: root, rally: kind == 1)
        installSuspension(on: root, dustRate: 11)
        return root
    }

    static func makeObstacle(kind: Int) -> SCNNode {
        if kind == 1 {
            if let wreck = importedDebris() { return wreck }
            let wreck = vehicleBody(color: rust, armored: false)
            wreck.addChildNode(box(1.5, 0.55, 1.5, rust, at: SCNVector3(0.1, 1.3, 0)))
            wreck.eulerAngles.y = 0.45
            let crushed = box(1.1, 0.08, 1.2, rust, at: SCNVector3(-0.25, 1.65, -0.1))
            crushed.eulerAngles.z = 0.25
            wreck.addChildNode(crushed)
            for offset: Float in [-0.7, 0.6] {
                let panel = box(0.8, 0.06, 0.6, rust, at: SCNVector3(offset, 0.06, 1.8))
                panel.eulerAngles.y = offset
                wreck.addChildNode(panel)
            }
            return wreck
        }
        let root = SCNNode()
        if kind == 0 {
            root.addChildNode(box(2.35, 0.9, 0.7, sand, at: SCNVector3(0, 0.45, 0)))
            root.childNodes.first?.geometry?.firstMaterial = surface("masonry", tint: sand)
            for x: Float in [-0.9, 0.8] {
                root.addChildNode(cylinder(radius: 0.025, height: 0.5, color: rust, at: SCNVector3(x, 1, 0)))
            }
            for x: Float in [-0.8, 0, 0.8] {
                let stripe = box(0.23, 0.65, 0.02, rust, at: SCNVector3(x, 0.5, 0.36))
                stripe.eulerAngles.z = -0.35
                root.addChildNode(stripe)
            }
        } else {
            let rock = terrainRock(radius: 0.7)
            rock.scale = SCNVector3(rock.scale.x * 1.15, rock.scale.y * 1.1, rock.scale.z)
            rock.position.y = 0.02
            root.addChildNode(rock)
        }
        return root
    }

    /// Faceted stone shared by the roadside and the boulder obstacles.
    private static func terrainRock(radius: Float) -> SCNNode {
        if let model = makeImportedEnvironment(name: "rock") {
            let copy = model.clone()
            let scale = radius / 0.42
            copy.scale = SCNVector3(scale * 1.35, scale * 0.72, scale * 1.05)
            return copy
        }
        return ellipsoid(radius: radius, scale: SCNVector3(1.5, 0.6, 1), color: sand, at: SCNVector3Zero)
    }

    static func makePedestrian(character: GujaratCharacter? = nil) -> SCNNode {
        let shirts = [
            UIColor(red: 0.53, green: 0.61, blue: 0.56, alpha: 1),
            UIColor(red: 0.62, green: 0.42, blue: 0.28, alpha: 1),
            UIColor(red: 0.28, green: 0.36, blue: 0.42, alpha: 1)
        ]
        let shirt = shirts[pedestrianShirt % shirts.count]
        let identity = character ?? GujaratCharacter.allCases[pedestrianShirt % GujaratCharacter.allCases.count]
        pedestrianShirt += 1
        if let person = loadedCharacter(shirt: shirt, pose: .standing, character: identity) { return person }
        let root = SCNNode()
        root.addChildNode(box(0.42, 0.72, 0.28, shirt, at: SCNVector3(0, 0.95, 0)))
        for x: Float in [-0.12, 0.12] { root.addChildNode(box(0.12, 0.55, 0.15, dark, at: SCNVector3(x, 0.3, 0))) }
        let head = SCNNode(geometry: SCNSphere(radius: 0.18))
        (head.geometry as? SCNSphere)?.segmentCount = 12
        head.geometry?.firstMaterial = material(UIColor(red: 0.63, green: 0.43, blue: 0.29, alpha: 1))
        head.position.y = 1.52
        root.addChildNode(head)
        return root
    }

    static func setNight(_ night: Bool, in root: SCNNode) {
        root.enumerateChildNodes { node, _ in
            if node.name == "litWindow" || node.name == "lampGlow" || node.name == "headlamp" {
                node.geometry?.firstMaterial?.emission.contents = night ? warm : UIColor.black
                if node.name == "litWindow" { node.geometry?.firstMaterial?.diffuse.contents = night ? warm : dark }
            }
            if node.name == "sunglasses" { node.isHidden = night }
            if node.name == "streetLight" { node.light?.intensity = night ? 380 : 0 }
            if node.name == "headlight" { node.light?.intensity = night ? 950 : 0 }
        }
    }

    private static func vehicleBody(color: UIColor, armored: Bool, chassis: Bool = true) -> SCNNode {
        let root = SCNNode()
        if chassis {
            root.addChildNode(box(1.85, 0.5, 3.1, color, at: SCNVector3(0, 0.8, 0)))
            root.addChildNode(box(1.9, 0.16, 0.2, dark, at: SCNVector3(0, 0.62, -1.6)))
        }
        for x: Float in [-1, 1] {
            for z: Float in [-1, 1] {
                let wheel = detailedWheel(radius: armored ? 0.5 : 0.43)
                wheel.name = "wheel"
                wheel.position = SCNVector3(x, 0.45, z)
                root.addChildNode(wheel)
                if chassis { root.addChildNode(box(0.12, 0.16, 1.35, rust, at: SCNVector3(x * 0.65, 0.39, z))) }
            }
            let headlamp = box(0.25, 0.25, 0.07, warm, at: SCNVector3(x * 0.65, 0.95, -1.57))
            headlamp.name = "headlamp"
            headlamp.geometry?.firstMaterial = headlamp.geometry?.firstMaterial?.copy() as? SCNMaterial
            root.addChildNode(headlamp)
            let light = SCNNode()
            light.name = "headlight"
            light.light = SCNLight()
            light.light?.type = .spot
            light.light?.color = UIColor(red: 1, green: 0.88, blue: 0.62, alpha: 1)
            light.light?.spotInnerAngle = 22
            light.light?.spotOuterAngle = 48
            light.light?.attenuationStartDistance = 2
            light.light?.attenuationEndDistance = 45
            light.light?.intensity = 0
            light.position = SCNVector3(x * 0.65, 1, -1.65)
            light.eulerAngles.x = -0.13
            root.addChildNode(light)
            root.addChildNode(box(0.18, 0.16, 0.06, UIColor.red, at: SCNVector3(x * 0.65, 0.85, 1.57)))
        }
        return root
    }

    /// Articulated seated silhouette with visible facial features at close camera range.
    private static func makeCharacter(skin: UIColor, shirt: UIColor, character: GujaratCharacter = .driver) -> SCNNode {
        if let loaded = loadedCharacter(shirt: shirt, character: character) { return loaded }
        let root = SCNNode()
        let torso = box(0.42, 0.52, 0.29, shirt, at: SCNVector3Zero)
        torso.geometry?.firstMaterial = surface("fabric", tint: shirt)
        root.addChildNode(torso)
        root.addChildNode(box(0.43, 0.07, 0.31, dark, at: SCNVector3(0, -0.23, 0)))
        root.addChildNode(cylinder(radius: 0.075, height: 0.14, color: skin, at: SCNVector3(0, 0.3, 0)))
        let head = ellipsoid(radius: 0.21, scale: SCNVector3(0.85, 1.16, 0.9), color: skin, at: SCNVector3(0, 0.48, -0.015))
        root.addChildNode(head)
        let hair = ellipsoid(radius: 0.205, scale: SCNVector3(0.88, 0.5, 0.95), color: dark, at: SCNVector3(0, 0.66, 0.005))
        root.addChildNode(hair)
        root.addChildNode(box(0.07, 0.1, 0.11, skin, at: SCNVector3(0, 0.47, -0.2)))
        root.addChildNode(box(0.08, 0.018, 0.02, rust, at: SCNVector3(0, 0.375, -0.18)))
        for side: Float in [-1, 1] {
            root.addChildNode(ellipsoid(radius: 0.048, scale: SCNVector3(0.6, 1.2, 0.8), color: skin, at: SCNVector3(side * 0.18, 0.48, -0.005)))
            root.addChildNode(box(0.055, 0.025, 0.018, .white, at: SCNVector3(side * 0.085, 0.53, -0.184)))
            root.addChildNode(box(0.02, 0.026, 0.02, dark, at: SCNVector3(side * 0.085, 0.53, -0.195)))
            root.addChildNode(box(0.07, 0.022, 0.03, dark, at: SCNVector3(side * 0.085, 0.57, -0.18)))
            let upper = box(0.13, 0.3, 0.14, shirt, at: SCNVector3(side * 0.25, 0.03, -0.08))
            upper.eulerAngles.x = -0.45
            root.addChildNode(upper)
            let forearm = box(0.1, 0.1, 0.3, skin, at: SCNVector3(side * 0.24, -0.03, -0.3))
            forearm.eulerAngles.x = 0.16
            root.addChildNode(forearm)
            root.addChildNode(ellipsoid(radius: 0.07, scale: SCNVector3(0.75, 0.7, 1), color: skin, at: SCNVector3(side * 0.23, -0.01, -0.45)))
            root.addChildNode(box(0.16, 0.16, 0.43, dark, at: SCNVector3(side * 0.12, -0.27, -0.18)))
            root.addChildNode(box(0.14, 0.37, 0.14, dark, at: SCNVector3(side * 0.12, -0.48, -0.35)))
            root.addChildNode(box(0.16, 0.13, 0.28, rust, at: SCNVector3(side * 0.12, -0.69, -0.41)))
        }
        return root
    }

    /// A bounded burst; the owner removes this complete node after 3.2 seconds.
    static func makeCrashEffects() -> SCNNode {
        let root = SCNNode()
        root.name = "crashEffects"
        for smoke in [false, true] {
            let emitter = SCNNode()
            emitter.position.y = smoke ? 0.65 : 0.3
            let particles = SCNParticleSystem()
            particles.loops = false
            particles.emissionDuration = smoke ? 0.9 : 0.12
            particles.birthRate = smoke ? 18 : 120
            particles.particleLifeSpan = smoke ? 1.9 : 0.45
            particles.particleLifeSpanVariation = 0.2
            particles.particleSize = smoke ? 0.35 : 0.055
            particles.particleSizeVariation = smoke ? 0.15 : 0.025
            particles.particleVelocity = smoke ? 1.6 : 5.5
            particles.particleVelocityVariation = smoke ? 0.5 : 2
            particles.emittingDirection = SCNVector3(0, 1, 0)
            particles.spreadingAngle = smoke ? 55 : 130
            particles.acceleration = smoke ? SCNVector3(0, 0.3, 0.4) : SCNVector3(0, -7, 0)
            particles.particleImage = texture("dust")
            particles.particleColor = smoke ? UIColor(white: 0.22, alpha: 0.45) : UIColor(red: 1, green: 0.62, blue: 0.12, alpha: 0.9)
            particles.blendMode = smoke ? .alpha : .additive
            particles.isLightingEnabled = false
            particles.isAffectedByGravity = false
            particles.isLocal = false
            let fade = CAKeyframeAnimation(keyPath: nil)
            fade.values = smoke ? [0, 0.5, 0.2, 0] : [1, 0.8, 0]
            fade.keyTimes = smoke ? [0, 0.1, 0.6, 1] : [0, 0.4, 1]
            particles.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
            emitter.addParticleSystem(particles)
            root.addChildNode(emitter)
        }
        return root
    }

    /// Reversible, scrubbed animation. The same progress poses the climb in both directions.
    static func poseDriver(in jeep: SCNNode, progress: Float, time: Float) {
        guard let driver = jeep.childNode(withName: "suspension", recursively: false)?.childNode(withName: "playerDriver", recursively: false),
              let rig = characterRigs.object(forKey: driver) else { return }
        let p = max(0, min(1, progress))
        let ease = p * p * (3 - 2 * p)
        let step = sin(p * .pi)
        let rise: Float = rig.isGujarat ? 0.45 : 0.53
        let travel: Float = rig.isGujarat ? 0.32 : 0.67
        driver.position = SCNVector3(0.45 * (1 - ease), 1.5 + ease * rise + step * 0.12, -0.02 + ease * travel)
        driver.eulerAngles.y = ease * .pi
        let breath = sin(time * 2.2) * 0.006
        rig.pose(seated: 1 - ease, step: step, breathing: breath)
    }

    private static let characterRigs = NSMapTable<SCNNode, CharacterRig>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private static var pedestrianShirt = 0
    private enum CharacterPose { case seated, standing }
    private static var characterAsset: CharacterAsset?
    private static var attemptedCharacterLoad = false
    private static var wheelTemplates: [Int: SCNNode] = [:]
    private static var opaqueMaterials: [String: SCNMaterial] = [:]
    private static var surfaceMaterials: [String: SCNMaterial] = [:]

    private static func loadedCharacter(shirt: UIColor, pose: CharacterPose = .seated,
                                        character: GujaratCharacter = .driver) -> SCNNode? {
        if let asset = GujaratCharacterAsset.load(character) {
            let root = SCNNode()
            let skeleton = asset.instantiate()
            if pose == .seated {
                skeleton.position.y = -1.18
                skeleton.eulerAngles.y = .pi
            }
            root.addChildNode(skeleton)
            let rig = CharacterRig(character: root, skeleton: skeleton)
            characterRigs.setObject(rig, forKey: root)
            if pose == .seated { rig.pose(seated: 1, step: 0, breathing: 0) }
            else { rig.poseStanding() }
            return root
        }
        if !attemptedCharacterLoad {
            attemptedCharacterLoad = true
            characterAsset = CharacterAsset.load()
        }
        guard let asset = characterAsset else { return nil }
        let root = SCNNode()
        let skeleton = asset.instantiate(shirt: shirt)
        if pose == .seated {
            skeleton.position.y = -1.18
            skeleton.eulerAngles.y = .pi
        }
        root.addChildNode(skeleton)
        let rig = CharacterRig(character: root, skeleton: skeleton)
        characterRigs.setObject(rig, forKey: root)
        if pose == .seated { rig.pose(seated: 1, step: 0, breathing: 0) }
        else { rig.poseStanding() }
        attachGrooming(to: root, style: groomCursor % 4, seated: pose == .seated)
        groomCursor += 1
        return root
    }

    /// Opposite feet and arms. Phase is radians; the pedestrian node faces the travel direction.
    static func poseWalker(_ node: SCNNode, phase: Float) {
        characterRigs.object(forKey: node)?.poseWalking(phase: phase)
    }

    private static var groomCursor = 0
    private static var hairMaterials: [Int: SCNMaterial] = [:]
    private static let hairShape: SCNGeometry = {
        let sphere = SCNSphere(radius: 0.13)
        sphere.segmentCount = 10
        return sphere
    }()

    private static func hairMaterial(style: Int) -> SCNMaterial {
        if let cached = hairMaterials[style] { return cached }
        let colors = [
            UIColor(red: 0.07, green: 0.05, blue: 0.045, alpha: 1),
            UIColor(red: 0.24, green: 0.13, blue: 0.07, alpha: 1),
            UIColor(red: 0.40, green: 0.18, blue: 0.09, alpha: 1),
            UIColor(white: 0.42, alpha: 1)
        ]
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colors[style % colors.count]
        material.roughness.contents = 0.68
        material.metalness.contents = 0.04
        hairMaterials[style] = material
        return material
    }

    /// Bind-space head features. Seated characters are yawed and dropped before this runs.
    private static func anchor(_ x: Float, _ y: Float, _ z: Float, seated: Bool) -> SCNVector3 {
        seated ? SCNVector3(-x, y - 1.18, -z) : SCNVector3(x, y, z)
    }

    private static func groomPiece(_ scale: SCNVector3, style: Int, at position: SCNVector3) -> SCNNode {
        let geometry = hairShape.copy() as! SCNGeometry
        geometry.firstMaterial = hairMaterial(style: style)
        let node = SCNNode(geometry: geometry)
        node.scale = scale
        node.position = position
        return node
    }

    private static func attachGrooming(to character: SCNNode, style: Int, seated: Bool) {
        guard let head = characterRigs.object(forKey: character)?.bones["Head"] else { return }
        let groom = SCNNode()
        groom.name = "groom"
        groom.addChildNode(groomPiece(SCNVector3(1.2, 0.55, 1.05), style: style, at: anchor(0, 1.7, -0.01, seated: seated)))
        if style == 1 || style == 2 {
            groom.addChildNode(groomPiece(SCNVector3(1.05, 0.7, 0.55), style: style, at: anchor(0, 1.58, -0.09, seated: seated)))
        }
        if style == 2 {
            groom.addChildNode(groomPiece(SCNVector3(0.55, 0.55, 0.55), style: style, at: anchor(0, 1.66, -0.12, seated: seated)))
        }
        if style == 3 {
            groom.addChildNode(groomPiece(SCNVector3(0.7, 0.45, 0.5), style: style, at: anchor(0, 1.56, 0.075, seated: seated)))
        }
        let brow = SCNMaterial()
        brow.lightingModel = .physicallyBased
        brow.diffuse.contents = UIColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1)
        brow.roughness.contents = 0.8
        for side: Float in [-1, 1] {
            let geometry = SCNBox(width: 0.046, height: 0.012, length: 0.012, chamferRadius: 0.002)
            geometry.firstMaterial = brow
            let node = SCNNode(geometry: geometry)
            node.position = anchor(side * 0.038, 1.675, 0.092, seated: seated)
            node.eulerAngles.z = side * 0.25
            groom.addChildNode(node)
        }
        character.addChildNode(groom)
        let local = head.simdWorldTransform.inverse * groom.simdWorldTransform
        groom.removeFromParentNode()
        head.addChildNode(groom)
        groom.simdTransform = local
    }

    private static func finished(_ node: SCNNode, _ material: SCNMaterial) -> SCNNode {
        node.geometry?.firstMaterial = material
        return node
    }

    private static let gunMetal: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.62, alpha: 1)
        material.metalness.contents = 0.92
        material.roughness.contents = 0.2
        material.clearCoat.contents = 0.45
        material.clearCoatRoughness.contents = 0.1
        return material
    }()

    private static let gunWood: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.28, green: 0.15, blue: 0.07, alpha: 1)
        material.roughness.contents = 0.62
        material.metalness.contents = 0.05
        return material
    }()

    /// Merge static triangles by shared material; preserve only independently animated nodes.
    private static func batchStaticChildren(in root: SCNNode, excluding names: Set<String>) {
        let batch = SCNNode()
        batch.name = "staticMesh"
        let children = root.childNodes.filter { !names.contains($0.name ?? "") }
        var meshes: [(SCNNode, simd_float4x4)] = []
        let inverse = root.simdWorldTransform.inverse
        for child in children {
            if child.geometry != nil { meshes.append((child, inverse * child.simdWorldTransform)) }
            child.enumerateChildNodes { node, _ in
                if node.geometry != nil { meshes.append((node, inverse * node.simdWorldTransform)) }
            }
        }
        // Bake the complete ancestor transform into each leaf before flattening.
        // SceneKit's primitive flattening path can discard transforms carried by
        // geometry-less grouping nodes (for example a whole building's offset).
        for (node, transform) in meshes {
            node.removeFromParentNode()
            batch.addChildNode(node)
            node.simdTransform = transform
        }
        for child in children where child.parent === root { child.removeFromParentNode() }
        if !batch.childNodes.isEmpty {
            let bounds = batch.boundingBox
            let mesh = batch.flattenedClone()
            // Flattened primitive buffers are generated lazily by SceneKit.
            // Explicit bounds keep culling correct before the first render.
            mesh.boundingBox = bounds
            root.addChildNode(mesh)
        }
    }

    private static let vehicleMotion = NSMapTable<SCNNode, VehicleMotion>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    /// Small direct-child rig: no scene traversal or geometry allocation during animation.
    static func animateVehicle(_ root: SCNNode, time: Float, speed: Float, impact: Float = 0, steering: Float = 0) {
        guard let body = root.childNode(withName: "suspension", recursively: false) else { return }
        let state: VehicleMotion
        if let cached = vehicleMotion.object(forKey: root) { state = cached }
        else { state = VehicleMotion(); vehicleMotion.setObject(state, forKey: root) }
        let dt = min(0.05, max(0, time - (state.previousTime ?? time)))
        let acceleration = dt > 0 ? max(-15, min(15, (speed - state.previousSpeed) / dt)) : 0
        state.previousTime = time
        state.previousSpeed = speed
        state.spin = (state.spin - speed * dt / 0.44).truncatingRemainder(dividingBy: .pi * 2)
        state.lean += (-max(-1, min(1, steering)) * 0.065 - state.lean) * min(1, dt * 9)
        state.pitch += (acceleration * 0.0025 - state.pitch) * min(1, dt * 7)
        let motion = min(1, max(0, speed / 18))
        body.position.y = (sin(time * 18) * 0.018 + sin(time * 27) * 0.009) * motion + impact * 0.09
        body.eulerAngles.x = sin(time * 12) * 0.009 * motion + impact * 0.055 + state.pitch
        body.eulerAngles.z = sin(time * 9) * 0.012 * motion + state.lean
        for wheel in root.childNodes where wheel.name == "wheel" {
            wheel.eulerAngles.x = state.spin
            let rideHeight: Float = (root as? ImportedVehicleNode)?.rideHeight ?? 0.45
            wheel.position.y = rideHeight + sin(time * 22 + wheel.position.z) * 0.012 * motion
            if wheel.position.z < 0 { wheel.eulerAngles.y = -max(-1, min(1, steering)) * 0.32 }
        }
        if let dust = root.childNode(withName: "vehicleDust", recursively: false)?.particleSystems?.first {
            dust.birthRate = CGFloat(speed > 1 ? min(20, speed * 0.65) : 0)
        }
    }

    private static var blendedSkies: [Int: UIImage] = [:]
    private static let sceneSkyIndices = NSMapTable<SCNScene, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    static func configureEnvironment(scene: SCNScene, night: Bool) {
        configureEnvironment(scene: scene, daylight: night ? 0 : 1)
    }

    /// Only 33 small sky textures can exist; IBL uses one fixed panorama to avoid prefilter churn.
    static func configureEnvironment(scene: SCNScene, daylight: Float) {
        let light = max(0, min(1, daylight))
        let index = Int((light * 32).rounded())
        let previous = sceneSkyIndices.object(forKey: scene)?.intValue
        if previous != index {
            if blendedSkies[index] == nil {
                let size = CGSize(width: 512, height: 256)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1; format.opaque = true; format.preferredRange = .standard
                let sky = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    let rect = CGRect(origin: .zero, size: size)
                    texture("skyNight").draw(in: rect)
                    texture("skyDay").draw(in: rect, blendMode: .normal, alpha: CGFloat(index) / 32)
                }
                // Explicit RGB bytes prevent UIKit's grayscale optimization from making R8_sRGB maps.
                guard let source = sky.cgImage,
                      let rgba = CGContext(data: nil, width: 512, height: 256, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                    preconditionFailure("Unable to allocate blended sky")
                }
                rgba.draw(source, in: CGRect(origin: .zero, size: size))
                guard let converted = rgba.makeImage() else { preconditionFailure("Unable to create blended sky") }
                blendedSkies[index] = UIImage(cgImage: converted, scale: 1, orientation: .up)
            }
            scene.background.contents = blendedSkies[index]
            if previous == nil { scene.lightingEnvironment.contents = texture("skyDay") }
            sceneSkyIndices.setObject(NSNumber(value: index), forKey: scene)
        }
        scene.lightingEnvironment.intensity = CGFloat(0.45 + light * 1.15)
    }

    private static func installSuspension(on root: SCNNode, dustRate: CGFloat) {
        let body = SCNNode()
        body.name = "suspension"
        for child in root.childNodes where child.name != "wheel" {
            child.removeFromParentNode()
            body.addChildNode(child)
        }
        // Imported bodies are already one cached mesh. Keep their vertex colors
        // and shared geometry intact instead of rebuilding them for every spawn.
        if !(root is ImportedVehicleNode) {
            batchStaticChildren(in: body, excluding: ["turret", "playerDriver", "pursuerDriver", "pursuerRider", "headlight", "headlamp", "sculptedBody"])
        }
        root.addChildNode(body)
        let emitter = SCNNode()
        emitter.name = "vehicleDust"
        emitter.position = SCNVector3(0, 0.12, 1.25)
        let dust = SCNParticleSystem()
        dust.birthRate = dustRate
        dust.particleLifeSpan = 0.85
        dust.particleLifeSpanVariation = 0.3
        dust.particleSize = 0.21
        dust.particleSizeVariation = 0.12
        dust.particleVelocity = 2.5
        dust.particleVelocityVariation = 1.1
        dust.emittingDirection = SCNVector3(0, 0.15, 1)
        dust.spreadingAngle = 45
        dust.acceleration = SCNVector3(0, 0.3, 0.7)
        dust.particleColor = UIColor(red: 0.75, green: 0.58, blue: 0.38, alpha: 1)
        dust.particleImage = texture("dust")
        dust.blendMode = .alpha
        dust.isLightingEnabled = false
        dust.isAffectedByGravity = false
        dust.isLocal = false
        dust.emitterShape = SCNBox(width: 1.7, height: 0.05, length: 0.1, chamferRadius: 0)
        let fade = CAKeyframeAnimation(keyPath: nil)
        fade.values = [0, 0.32, 0.14, 0]
        fade.keyTimes = [0, 0.15, 0.6, 1]
        let growth = CAKeyframeAnimation(keyPath: nil)
        growth.values = [0.18, 0.6, 1.05]
        growth.keyTimes = [0, 0.45, 1]
        dust.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade), .size: SCNParticlePropertyController(animation: growth)]
        emitter.addParticleSystem(dust)
        root.addChildNode(emitter)
    }

    private static func addJeepDetails(to root: SCNNode) {
        let steel = UIColor(white: 0.35, alpha: 1)
        for x: Float in [-0.69, -0.46, -0.23, 0, 0.23, 0.46, 0.69] {
            root.addChildNode(box(0.09, 0.29, 0.04, dark, at: SCNVector3(x, 0.98, -1.57)))
        }
        for side: Float in [-1, 1] {
            root.addChildNode(box(0.35, 0.08, 0.9, sand, at: SCNVector3(side * 0.98, 1.02, -0.95)))
            root.addChildNode(box(0.13, 0.06, 0.17, steel, at: SCNVector3(side * 0.85, 1.28, -0.63)))
            root.addChildNode(box(0.09, 0.38, 0.07, steel, at: SCNVector3(side * 0.96, 1.54, -0.1)))
            let mirror = box(0.23, 0.23, 0.06, steel, at: SCNVector3(side * 1.02, 1.74, -0.09))
            mirror.geometry?.firstMaterial = mirror.geometry?.firstMaterial?.copy() as? SCNMaterial
            mirror.geometry?.firstMaterial?.metalness.contents = 0.9
            mirror.geometry?.firstMaterial?.roughness.contents = 0.2
            root.addChildNode(mirror)
            root.addChildNode(box(0.11, 0.09, 0.75, dark, at: SCNVector3(side * 0.97, 0.57, 0.2)))
            root.addChildNode(box(0.09, 0.5, 0.06, steel, at: SCNVector3(side * 0.8, 1.45, 0.77)))
        }
        let arch = fenderArch(color: UIColor(red: 0.32, green: 0.37, blue: 0.22, alpha: 1))
        for x: Float in [-0.98, 0.98] {
            for z: Float in [-1, 1] {
                let fender = SCNNode(geometry: arch)
                fender.position = SCNVector3(x, 0.43, z)
                fender.eulerAngles.y = .pi / 2
                root.addChildNode(fender)
            }
        }
        // Vent slots and a dirty hood seam.
        for z: Float in [-1.15, -1.03, -0.91, -0.79] {
            root.addChildNode(box(0.85, 0.012, 0.035, dark, at: SCNVector3(0, 1.285, z)))
        }
        root.addChildNode(box(0.015, 0.012, 1.02, rust, at: SCNVector3(0, 1.29, -0.85)))
        let steering = SCNNode(geometry: SCNTorus(ringRadius: 0.18, pipeRadius: 0.022))
        steering.geometry?.firstMaterial = material(dark)
        steering.eulerAngles.x = .pi / 2 - 0.4
        steering.position = SCNVector3(0.45, 1.48, -0.47)
        root.addChildNode(steering)
        root.addChildNode(box(1.5, 0.2, 0.16, dark, at: SCNVector3(0, 1.38, -0.3)))
        for x: Float in [0.3, 0.45, 0.6] {
            let gauge = cylinder(radius: 0.045, height: 0.015, color: UIColor(white: 0.75, alpha: 1), at: SCNVector3(x, 1.4, -0.205))
            gauge.eulerAngles.x = .pi / 2
            root.addChildNode(gauge)
        }
        let fuel = box(0.4, 0.63, 0.2, rust, at: SCNVector3(-0.62, 1.15, 1.62))
        root.addChildNode(fuel)
        root.addChildNode(box(0.19, 0.09, 0.13, dark, at: SCNVector3(-0.62, 1.49, 1.62)))
        attachSunglasses(to: root)
    }

    private static func attachSunglasses(to root: SCNNode) {
        guard let driver = root.childNode(withName: "playerDriver", recursively: true) else { return }
        // The supplied driver wears the source pack's head-bound goggles and reflection lenses.
        if driver.childNode(withName: "sunglassLens", recursively: true) != nil { return }
        let glasses = SCNNode()
        glasses.name = "sunglasses"
        for side: Float in [-1, 1] {
            glasses.addChildNode(box(0.16, 0.09, 0.035, dark, at: SCNVector3(side * 0.087, 0.535, -0.192)))
            let lens = box(0.135, 0.063, 0.006, UIColor(red: 0.13, green: 0.22, blue: 0.25, alpha: 1), at: SCNVector3(side * 0.087, 0.535, -0.214))
            lens.name = "sunglassLens"
            lens.categoryBitMask = 2
            let glass = SCNMaterial()
            glass.lightingModel = .physicallyBased
            glass.diffuse.contents = UIColor(red: 0.08, green: 0.19, blue: 0.23, alpha: 1)
            glass.metalness.contents = 0.95
            glass.roughness.contents = 0.08
            lens.geometry?.firstMaterial = glass
            glasses.addChildNode(lens)
            glasses.addChildNode(box(0.018, 0.025, 0.19, dark, at: SCNVector3(side * 0.17, 0.55, -0.1)))
        }
        glasses.addChildNode(box(0.05, 0.018, 0.025, dark, at: SCNVector3(0, 0.55, -0.21)))
        driver.addChildNode(glasses)
        if let rig = characterRigs.object(forKey: driver), let head = rig.bones["Head"] {
            let local = head.simdWorldTransform.inverse * glasses.simdWorldTransform
            glasses.removeFromParentNode()
            head.addChildNode(glasses)
            glasses.simdTransform = local
        }
    }

    private static var environmentAsset: ImportedEnvironmentAsset?
    private static var attemptedEnvironmentLoad = false

    private static func makeImportedEnvironment(name: String) -> SCNNode? {
        if !attemptedEnvironmentLoad {
            attemptedEnvironmentLoad = true
            environmentAsset = ImportedEnvironmentAsset.load()
        }
        return environmentAsset?.instantiate(name: name)
    }

    private static func placeLot(side: Float, z: Float, street: Float, model: Int, ruined: Bool,
                                 rng: inout SeededRandom, roadHeight: (Float, Float) -> Float, into root: SCNNode) {
        guard let building = makeImportedBuilding(type: model, ruined: ruined) else { return }
        let bounds = building.boundingBox
        let depth = bounds.max.z - bounds.min.z
        let width = bounds.max.x - bounds.min.x
        let x = side * (street + depth / 2 + rng.range(0, 0.9))
        var low: Float = .greatestFiniteMagnitude
        var high: Float = -.greatestFiniteMagnitude
        for dz in [-width / 2, width / 2] {
            let h = roadHeight(side * 5.7, z + dz)
            low = min(low, h); high = max(high, h)
        }
        let base = high + 0.025
        let foundationHeight = max(0.18, high - low + 0.25)
        root.addChildNode(box(depth + 0.1, foundationHeight, width + 0.1, sand,
                              at: SCNVector3(x, base - foundationHeight / 2, z)))
        building.position = SCNVector3(x, base, z)
        building.eulerAngles.y = side * .pi / 2
        root.addChildNode(building)
        if ruined, street < 12, let fence = makeImportedEnvironment(name: "fence_open") {
            fence.position = SCNVector3(side * (street - 0.4), roadHeight(side * 5.7, z + 3) - 0.03, z + 3)
            fence.eulerAngles.y = side * .pi / 2
            root.addChildNode(fence)
        }
    }

    /// Flat-roof adobe compounds sit behind the street wall, in the same plaster palette.
    private static func placeDesertHome(side: Float, z: Float, street: Float, model: Int,
                                        roadHeight: (Float, Float) -> Float, into root: SCNNode) {
        let names = ["desert_bg01", "desert_bg02", "desert_bg03", "desert_bg04"]
        guard let building = makeImportedEnvironment(name: names[model % names.count]) else { return }
        building.name = "importedBuilding"
        let bounds = building.boundingBox
        let depth = bounds.max.z - bounds.min.z
        let width = bounds.max.x - bounds.min.x
        let x = side * (street + depth / 2)
        var high: Float = -.greatestFiniteMagnitude
        for dz in [-width / 2, width / 2] {
            high = max(high, roadHeight(side * 5.7, z + dz))
        }
        building.position = SCNVector3(x, high + 0.02, z)
        building.eulerAngles.y = side * .pi / 2
        root.addChildNode(building)
    }

    private static func makeImportedBuilding(type: Int, ruined: Bool) -> SCNNode? {
        let names = ["house_type01", "house_type02", "house_type06", "house_type08", "house_type10", "house_type17"]
        let node = makeImportedEnvironment(name: names[type % names.count] + (ruined ? "-ruin" : ""))
        node?.name = "importedBuilding"
        return node
    }

    /// Shared analytic heights generate both the visible road and tire contact.
    private static func groundMesh(x: ClosedRange<Float>, z: ClosedRange<Float>, columns: Int, rows: Int,
                                   material: SCNMaterial, height: (Float, Float) -> Float) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uv: [CGPoint] = []
        var indices: [UInt32] = []
        for row in 0...rows {
            let pz = z.lowerBound + (z.upperBound - z.lowerBound) * Float(row) / Float(rows)
            for column in 0...columns {
                let px = x.lowerBound + (x.upperBound - x.lowerBound) * Float(column) / Float(columns)
                let epsilon: Float = 0.05
                let dx = (height(px + epsilon, pz) - height(px - epsilon, pz)) / (2 * epsilon)
                let dz = (height(px, pz + epsilon) - height(px, pz - epsilon)) / (2 * epsilon)
                let normal = simd_normalize(SIMD3<Float>(-dx, 1, -dz))
                vertices.append(SCNVector3(px, height(px, pz), pz))
                normals.append(SCNVector3(normal.x, normal.y, normal.z))
                uv.append(CGPoint(x: CGFloat(column) / CGFloat(columns), y: CGFloat(row) / CGFloat(rows)))
                if row < rows && column < columns {
                    let a = UInt32(row * (columns + 1) + column)
                    let b = a + 1, c = a + UInt32(columns + 1), d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
        }
        let data = indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)], elements: [element])
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private static var vehicleAssets: [String: ImportedVehicleAsset] = [:]

    private static func importedPursuer(kind: Int) -> SCNNode? {
        let name = kind == 1 ? "hatchback-sports" : "suv"
        if vehicleAssets[name] == nil { vehicleAssets[name] = ImportedVehicleAsset.load(name: name) }
        guard let asset = vehicleAssets[name] else { return nil }
        let root = asset.instantiate()
        root.name = kind == 1 ? "rallyCar" : "armoredSUV"
        let driver = makeCharacter(skin: UIColor(red: 0.55, green: 0.36, blue: 0.24, alpha: 1), shirt: rust, character: kind == 1 ? .driver : .grandpa)
        driver.name = "pursuerDriver"
        driver.position = SCNVector3(0.35, 1.02, -0.15)
        driver.scale = SCNVector3(0.78, 0.78, 0.78)
        root.addChildNode(driver)
        // The original curved vehicle body and glazing remain the visible silhouette.
        // Only working light sources and the animated occupant are added.
        for side: Float in [-1, 1] {
            let light = SCNNode()
            light.name = "headlight"
            light.light = SCNLight()
            light.light?.type = .spot
            light.light?.color = warm
            light.light?.spotInnerAngle = 20
            light.light?.spotOuterAngle = 42
            light.light?.attenuationStartDistance = 2
            light.light?.attenuationEndDistance = 38
            light.light?.intensity = 0
            light.position = SCNVector3(side * 0.55, 0.72, -1.92)
            light.eulerAngles.x = -0.13
            root.addChildNode(light)
            let lamp = box(0.22, 0.11, 0.025, warm, at: light.position)
            lamp.name = "headlamp"
            lamp.geometry?.firstMaterial = lamp.geometry?.firstMaterial?.copy() as? SCNMaterial
            root.addChildNode(lamp)
        }
        installSuspension(on: root, dustRate: 11)
        return root
    }

    private static func importedBike() -> SCNNode? {
        if vehicleAssets["bike"] == nil { vehicleAssets["bike"] = ImportedVehicleAsset.load(name: "bike") }
        guard let asset = vehicleAssets["bike"] else { return nil }
        let root = asset.instantiate()
        root.name = "pursuitBike"
        let rider = makeCharacter(skin: UIColor(red: 0.62, green: 0.40, blue: 0.27, alpha: 1), shirt: rust, character: .explorer)
        rider.name = "pursuerRider"
        rider.position = SCNVector3(0, 1.04, 0.16)
        rider.scale = SCNVector3(0.88, 0.88, 0.88)
        root.addChildNode(rider)
        let headlamp = box(0.16, 0.12, 0.04, warm, at: SCNVector3(0, 0.9, -0.78))
        headlamp.name = "headlamp"
        headlamp.geometry?.firstMaterial = headlamp.geometry?.firstMaterial?.copy() as? SCNMaterial
        root.addChildNode(headlamp)
        let light = SCNNode()
        light.name = "headlight"
        light.light = SCNLight()
        light.light?.type = .spot
        light.light?.color = warm
        light.light?.spotInnerAngle = 18
        light.light?.spotOuterAngle = 36
        light.light?.attenuationEndDistance = 30
        light.light?.intensity = 0
        light.position = SCNVector3(0, 0.9, -0.86)
        light.eulerAngles.x = -0.13
        root.addChildNode(light)
        installSuspension(on: root, dustRate: 7)
        return root
    }

    private static func importedDebris() -> SCNNode? {
        if vehicleAssets["hatchback-sports"] == nil {
            vehicleAssets["hatchback-sports"] = ImportedVehicleAsset.load(name: "hatchback-sports")
        }
        guard let asset = vehicleAssets["hatchback-sports"] else { return nil }
        let wreck = asset.instantiate()
        wreck.eulerAngles = SCNVector3(0.22, 0.55, 0.38)
        return wreck
    }

    private static func fenderArch(color: UIColor) -> SCNGeometry {
        let path = UIBezierPath()
        path.addArc(withCenter: .zero, radius: 0.61, startAngle: 0, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: -0.49, y: 0))
        path.addArc(withCenter: .zero, radius: 0.49, startAngle: .pi, endAngle: 0, clockwise: false)
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.22)
        shape.chamferRadius = 0.015
        shape.firstMaterial = material(color)
        return shape
    }

    private static func addCarDetails(to root: SCNNode, rally: Bool) {
        for side: Float in [-1, 1] {
            root.addChildNode(box(0.08, 0.12, 1.5, sand, at: SCNVector3(side * 0.95, 0.65, 0)))
            root.addChildNode(box(0.12, 0.1, 0.3, dark, at: SCNVector3(side * 0.97, 1.03, 0.4)))
            root.addChildNode(box(0.25, 0.18, 0.16, dark, at: SCNVector3(side * 0.95, 1.48, -0.56)))
            let number = box(0.02, 0.42, 0.48, .white, at: SCNVector3(side * 0.942, 0.95, 0.12))
            number.geometry?.firstMaterial = surface(rally ? "number" : "paint", tint: rally ? .white : dark)
            root.addChildNode(number)
        }
        for x: Float in [-0.55, -0.28, 0, 0.28, 0.55] {
            root.addChildNode(box(0.15, 0.22, 0.03, dark, at: SCNVector3(x, 0.94, -1.57)))
        }
        root.addChildNode(box(0.7, 0.07, 0.32, dark, at: SCNVector3(0, 1.12, -0.94)))
    }

    private static func detailedWheel(radius: Float) -> SCNNode {
        let key = Int(radius * 100)
        if let cached = wheelTemplates[key] { return cached.clone() }
        let root = SCNNode()
        let tire = cylinder(radius: radius, height: 0.35, color: dark, at: SCNVector3Zero)
        tire.eulerAngles.z = .pi / 2
        (tire.geometry as? SCNCylinder)?.radialSegmentCount = 20
        tire.geometry?.firstMaterial = surface("rubber", tint: UIColor(white: 0.23, alpha: 1))
        root.addChildNode(tire)
        for side: Float in [-1, 1] {
            let hub = cylinder(radius: radius * 0.53, height: 0.025, color: UIColor(white: 0.49, alpha: 1), at: SCNVector3(side * 0.185, 0, 0))
            hub.eulerAngles.z = .pi / 2
            hub.geometry?.firstMaterial = hub.geometry?.firstMaterial?.copy() as? SCNMaterial
            hub.geometry?.firstMaterial?.metalness.contents = 0.75
            root.addChildNode(hub)
            for i in 0..<5 {
                let angle = Float(i) * .pi * 2 / 5
                let bolt = cylinder(radius: 0.025, height: 0.035, color: dark, at: SCNVector3(side * 0.205, cos(angle) * radius * 0.3, sin(angle) * radius * 0.3))
                bolt.eulerAngles.z = .pi / 2
                root.addChildNode(bolt)
            }
        }
        for i in 0..<14 {
            let angle = Float(i) * .pi * 2 / 14
            let tread = box(0.36, 0.055, 0.13, dark, at: SCNVector3(0, cos(angle) * radius, sin(angle) * radius))
            tread.eulerAngles.x = angle
            root.addChildNode(tread)
        }
        let bounds = root.boundingBox
        let result = root.flattenedClone()
        result.boundingBox = bounds
        wheelTemplates[key] = result
        return result.clone()
    }

    private static func makeBarrel() -> SCNNode {
        let root = SCNNode()
        let drum = cylinder(radius: 0.29, height: 0.85, color: rust, at: SCNVector3(0, 0.425, 0))
        drum.geometry?.firstMaterial = surface("rust", tint: rust)
        root.addChildNode(drum)
        for y: Float in [0.12, 0.73] {
            root.addChildNode(cylinder(radius: 0.305, height: 0.04, color: dark, at: SCNVector3(0, y, 0)))
        }
        root.addChildNode(cylinder(radius: 0.06, height: 0.02, color: dark, at: SCNVector3(0.13, 0.86, 0)))
        let bounds = root.boundingBox
        let result = root.flattenedClone()
        result.boundingBox = bounds
        return result
    }

    private static func ellipsoid(radius: Float, scale: SCNVector3, color: UIColor, at position: SCNVector3) -> SCNNode {
        let geometry = SCNSphere(radius: CGFloat(radius))
        geometry.segmentCount = 16
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.scale = scale
        node.position = position
        return node
    }

    private static func surface(_ kind: String, tint: UIColor, repeatX: Float = 1, repeatY: Float = 1) -> SCNMaterial {
        let key = "\(kind)-\(colorKey(tint))-\(repeatX)-\(repeatY)"
        if let cached = surfaceMaterials[key] { return cached }
        let result = material(tint).copy() as! SCNMaterial
        result.diffuse.contents = texture(kind)
        result.diffuse.wrapS = .repeat
        result.diffuse.wrapT = .repeat
        result.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        result.normal.contents = texture("normal")
        result.normal.intensity = kind == "asphalt" || kind == "masonry" ? 0.3 : 0.12
        result.normal.wrapS = .repeat
        result.normal.wrapT = .repeat
        result.normal.contentsTransform = result.diffuse.contentsTransform
        result.roughness.contents = kind == "rubber" ? 1 : 0.88
        result.metalness.contents = kind == "rust" ? 0.5 : 0.04
        if surfaceMaterials.count < 128 { surfaceMaterials[key] = result }
        return result
    }

    /// Deterministic, shared 512 px surfaces: no asset downloads or per-chunk image allocation.
    private static var sceneryCache: [String: SCNMaterial] = [:]

    /// One plaster, wood, or sand material shared by every imported building.
    fileprivate static func sceneryMaterial(_ kind: String) -> SCNMaterial {
        if let cached = sceneryCache[kind] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = texture(kind)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = kind == "sand" ? 0.96 : 0.9
        material.metalness.contents = 0
        material.shaderModifiers = [.geometry: """
        #pragma body
        float3 p = _geometry.position.xyz;
        float3 n = abs(_geometry.normal);
        float2 uv = p.xy;
        if (n.x >= n.y && n.x >= n.z) uv = p.zy;
        else if (n.y >= n.z) uv = p.xz;
        _geometry.texcoords[0] = uv * 0.55;
        """]
        sceneryCache[kind] = material
        return material
    }

    fileprivate static func windowGlass() -> SCNMaterial {
        if let cached = sceneryCache["window"] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.12, green: 0.16, blue: 0.17, alpha: 1)
        material.roughness.contents = 0.14
        material.metalness.contents = 0.22
        sceneryCache["window"] = material
        return material
    }

    fileprivate static func texture(_ kind: String) -> UIImage {
        if let cached = textureCache[kind] { return cached }
        let sky = kind.hasPrefix("sky")
        let size = CGSize(width: sky ? 1024 : 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = kind != "dust"
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            var rng = SeededRandom(state: UInt64(kind.utf8.reduce(0) { $0 &+ UInt64($1) }) &+ 4721)
            if kind == "normal" {
                UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                for _ in 0..<4500 {
                    UIColor(red: CGFloat(rng.range(0.43, 0.57)), green: CGFloat(rng.range(0.43, 0.57)), blue: 0.99, alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat(rng.range(0, 512)), y: CGFloat(rng.range(0, 512)), width: 3, height: 3))
                }
                return
            }
            if kind == "dust" {
                let colors = [UIColor.white.withAlphaComponent(0.85).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    context.drawRadialGradient(gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0, endCenter: CGPoint(x: 256, y: 256), endRadius: 250, options: [])
                }
                return
            }
            if sky {
                let night = kind == "skyNight"
                let top = night ? UIColor(red: 0.015, green: 0.025, blue: 0.07, alpha: 1) : UIColor(red: 0.25, green: 0.46, blue: 0.63, alpha: 1)
                let horizon = night ? UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1) : UIColor(red: 0.92, green: 0.72, blue: 0.47, alpha: 1)
                let bottom = night ? UIColor(red: 0.025, green: 0.025, blue: 0.035, alpha: 1) : UIColor(red: 0.30, green: 0.22, blue: 0.15, alpha: 1)
                let colors = [top.cgColor, horizon.cgColor, bottom.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
                }
                if night {
                    for _ in 0..<190 {
                        UIColor.white.withAlphaComponent(CGFloat(rng.range(0.15, 0.8))).setFill()
                        let radius = CGFloat(rng.range(0.5, 1.5))
                        context.fillEllipse(in: CGRect(x: CGFloat(rng.range(0, 1024)), y: CGFloat(rng.range(0, 210)), width: radius, height: radius))
                    }
                } else {
                    UIColor(red: 1, green: 0.95, blue: 0.72, alpha: 1).setFill()
                    context.fillEllipse(in: CGRect(x: 660, y: 125, width: 28, height: 28))
                    // Thin haze bands give reflected glass a legible sky/horizon split.
                    for _ in 0..<18 {
                        UIColor.white.withAlphaComponent(0.025).setFill()
                        context.fill(CGRect(x: CGFloat(rng.range(0, 1024)), y: CGFloat(rng.range(70, 200)), width: CGFloat(rng.range(80, 300)), height: CGFloat(rng.range(2, 8))))
                    }
                }
                return
            }
            UIColor(white: kind == "rubber" ? 0.52 : 0.82, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<6500 {
                let value = CGFloat(rng.range(kind == "asphalt" ? 0.38 : 0.55, 0.97))
                UIColor(white: value, alpha: CGFloat(rng.range(0.15, 0.6))).setFill()
                let width = CGFloat(rng.range(0.6, kind == "sand" ? 3.6 : 2.2))
                context.fill(CGRect(x: CGFloat(rng.range(0, 512)), y: CGFloat(rng.range(0, 512)), width: width, height: width))
            }
            if kind == "sand" || kind == "fabric" || kind == "rubber" {
                context.setStrokeColor(UIColor(white: 0.25, alpha: kind == "sand" ? 0.09 : 0.16).cgColor)
                context.setLineWidth(kind == "rubber" ? 2 : 0.7)
                let spacing = kind == "rubber" ? 12 : 5
                for y in stride(from: 0, through: 512, by: spacing) {
                    context.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: 0, through: 512, by: 16) {
                        let wave = kind == "sand" ? sin(CGFloat(x) * 0.03) * 4 : 0
                        context.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y) + wave))
                    }
                }
                context.strokePath()
            }
            if kind == "gloss" {
                UIColor(white: 0.18, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                for _ in 0..<1600 {
                    UIColor(white: CGFloat(rng.range(0.08, 0.32)), alpha: 1).setFill()
                    let width = CGFloat(rng.range(1, 3))
                    context.fill(CGRect(x: CGFloat(rng.range(0, 512)), y: CGFloat(rng.range(0, 512)), width: width, height: width))
                }
                return
            }
            if kind == "plaster" || kind == "wood" {
                UIColor(white: kind == "wood" ? 0.78 : 0.9, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                for _ in 0..<2400 {
                    UIColor(white: CGFloat(rng.range(0.55, 1)), alpha: CGFloat(rng.range(0.15, 0.45))).setFill()
                    let width = CGFloat(rng.range(1, kind == "wood" ? 2 : 4))
                    let height = kind == "wood" ? CGFloat(rng.range(8, 28)) : width
                    context.fill(CGRect(x: CGFloat(rng.range(0, 512)), y: CGFloat(rng.range(0, 512)), width: width, height: height))
                }
                context.setStrokeColor(UIColor(white: 0.25, alpha: kind == "wood" ? 0.28 : 0.18).cgColor)
                context.setLineWidth(kind == "wood" ? 1.4 : 0.8)
                let lines = kind == "wood" ? 28 : 7
                for _ in 0..<lines {
                    let x = CGFloat(rng.range(0, 512))
                    let y = CGFloat(rng.range(0, 512))
                    context.move(to: CGPoint(x: x, y: y))
                    context.addLine(to: CGPoint(x: x + CGFloat(rng.range(-6, 8)), y: y + CGFloat(rng.range(20, 90))))
                }
                context.strokePath()
                return
            }
            if kind == "masonry" {
                context.setStrokeColor(UIColor(white: 0.32, alpha: 0.4).cgColor)
                context.setLineWidth(3)
                for row in 0..<8 {
                    let y = CGFloat(row) * 64
                    context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: 512, y: y))
                    for column in 0..<5 {
                        let x = CGFloat(column) * 128 + (row % 2 == 0 ? 0 : 64)
                        context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: x, y: y + 64))
                    }
                }
                context.strokePath()
            }
            if kind == "asphalt" || kind == "rust" || kind == "paint" {
                for _ in 0..<50 {
                    context.setStrokeColor(UIColor(white: kind == "rust" ? 0.2 : 0.35, alpha: 0.25).cgColor)
                    context.setLineWidth(CGFloat(rng.range(0.5, 2)))
                    let x = CGFloat(rng.range(0, 512)), y = CGFloat(rng.range(0, 512))
                    context.move(to: CGPoint(x: x, y: y))
                    context.addLine(to: CGPoint(x: x + CGFloat(rng.range(-10, 18)), y: y + CGFloat(rng.range(5, 50))))
                    context.strokePath()
                }
            }
            if kind == "sign" || kind == "number" {
                let title = kind == "number" ? "07" : "FUEL • REPAIRS"
                let font = UIFont.monospacedSystemFont(ofSize: kind == "number" ? 220 : 48, weight: .black)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: kind == "number" ? UIColor.black : UIColor(red: 0.89, green: 0.72, blue: 0.42, alpha: 1)]
                if kind == "sign" { UIColor(red: 0.13, green: 0.24, blue: 0.21, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size)) }
                let measured = title.size(withAttributes: attributes)
                title.draw(at: CGPoint(x: (512 - measured.width) / 2, y: (512 - measured.height) / 2), withAttributes: attributes)
            }
        }
        // UIKit can optimize monochrome images to single-channel sRGB formats.
        // Metal's simulator backend does not support R8Unorm_sRGB textures, so
        // force every map (including grayscale paint and dust) to RGBA8.
        guard let source = image.cgImage,
              let rgba = CGContext(data: nil, width: source.width, height: source.height,
                                   bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            preconditionFailure("Unable to allocate procedural RGBA texture")
        }
        rgba.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let converted = rgba.makeImage() else {
            preconditionFailure("Unable to create procedural RGBA texture")
        }
        let result = UIImage(cgImage: converted, scale: 1, orientation: .up)
        textureCache[kind] = result
        return result
    }

    private static func cactus(at position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.position = position
        let green = UIColor(red: 0.27, green: 0.35, blue: 0.22, alpha: 1)
        root.addChildNode(cylinder(radius: 0.18, height: 2.8, color: green, at: SCNVector3(0, 1.4, 0)))
        for side: Float in [-1, 1] {
            root.addChildNode(box(0.65, 0.22, 0.22, green, at: SCNVector3(side * 0.32, 1.35, 0)))
            root.addChildNode(cylinder(radius: 0.12, height: 0.9, color: green, at: SCNVector3(side * 0.6, 1.7, 0)))
        }
        return root
    }

    private static func box(_ width: Float, _ height: Float, _ length: Float, _ color: UIColor, at position: SCNVector3) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: CGFloat(min(0.025, min(width, min(height, length)) * 0.08)))
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private static func cylinder(radius: Float, height: Float, color: UIColor, at position: SCNVector3) -> SCNNode {
        let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
        geometry.radialSegmentCount = 10
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(Int((r * 20).rounded()))-\(Int((g * 20).rounded()))-\(Int((b * 20).rounded()))-\(Int((a * 20).rounded()))"
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let key = colorKey(color)
        if color.cgColor.alpha == 1, let cached = opaqueMaterials[key] { return cached }
        let result = SCNMaterial()
        result.diffuse.contents = texture("paint")
        result.multiply.contents = color
        result.roughness.contents = 0.82
        result.metalness.contents = 0.12
        result.lightingModel = .physicallyBased
        let alpha = color.cgColor.alpha
        if alpha < 1 {
            // Keep the close-up driver readable through glass while preserving sky reflections.
            result.transparency = alpha
            result.roughness.contents = 0.12
            result.metalness.contents = 0.28
            result.blendMode = .alpha
            result.writesToDepthBuffer = false
            result.isDoubleSided = true
        }
        if alpha == 1, opaqueMaterials.count < 128 { opaqueMaterials[key] = result }
        return result
    }
}

private struct SeededRandom {
    var state: UInt64
    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return lower + Float(value & 0xFFFFFF) / Float(0xFFFFFF) * (upper - lower)
    }
}

/// Curated Quaternius glTF data keeps its original skin weights; geometry is shared by all actors.
@MainActor
private final class CharacterAsset {
    struct Slice: Decodable { let offset: Int; let count: Int }
    struct Joint: Decodable {
        let name: String
        let translation: [Float]
        let rotation: [Float]
        let scale: [Float]
        let children: [Int]
    }
    struct Mesh: Decodable {
        let name: String
        let positions: Slice
        let normals: Slice
        let uv: Slice
        let joints: Slice
        let weights: Slice
        let triangles: [Slice]
        let face: Bool
    }
    struct Manifest: Decodable {
        let nodes: [Joint]
        let joints: [Int]
        let inverseBind: Slice
        let meshes: [Mesh]
        let root: Int
    }
    let manifest: Manifest
    let data: Data
    let geometries: [SCNGeometry]
    let weights: [SCNGeometrySource]
    let indices: [SCNGeometrySource]
    let inverseBind: [NSValue]
    let skin: UIImage?
    let eyes: UIImage?

    static func load() -> CharacterAsset? {
        func resource(_ name: String, _ ext: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Assets") ?? Bundle.main.url(forResource: name, withExtension: ext)
        }
        guard let manifestURL = resource("DriverMesh", "json"), let binaryURL = resource("DriverMesh", "bin"),
              let json = try? Data(contentsOf: manifestURL), let data = try? Data(contentsOf: binaryURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: json) else { return nil }
        return CharacterAsset(manifest: manifest, data: data,
                              skin: resource("DriverSkin", "png").flatMap { UIImage(contentsOfFile: $0.path) },
                              eyes: resource("DriverEyes", "png").flatMap { UIImage(contentsOfFile: $0.path) })
    }

    private init(manifest: Manifest, data: Data, skin: UIImage?, eyes: UIImage?) {
        self.manifest = manifest
        self.data = data
        self.skin = skin
        self.eyes = eyes
        func source(_ slice: Slice, _ semantic: SCNGeometrySource.Semantic, components: Int, bytes: Int = 4, floats: Bool = true) -> SCNGeometrySource {
            let packed = data.subdata(in: slice.offset..<(slice.offset + slice.count * components * bytes))
            return SCNGeometrySource(data: packed, semantic: semantic, vectorCount: slice.count, usesFloatComponents: floats,
                                     componentsPerVector: components, bytesPerComponent: bytes, dataOffset: 0, dataStride: components * bytes)
        }
        geometries = manifest.meshes.map { mesh in
            let elements = mesh.triangles.map { slice in
                SCNGeometryElement(data: data.subdata(in: slice.offset..<(slice.offset + slice.count * 4)), primitiveType: .triangles, primitiveCount: slice.count / 3, bytesPerIndex: 4)
            }
            return SCNGeometry(sources: [source(mesh.positions, .vertex, components: 3), source(mesh.normals, .normal, components: 3), source(mesh.uv, .texcoord, components: 2)], elements: elements)
        }
        weights = manifest.meshes.map { source($0.weights, .boneWeights, components: 4) }
        indices = manifest.meshes.map { source($0.joints, .boneIndices, components: 4, bytes: 2, floats: false) }
        inverseBind = (0..<manifest.inverseBind.count).map { index in
            let offset = manifest.inverseBind.offset + index * 64
            var matrix = matrix_identity_float4x4
            for column in 0..<4 {
                for row in 0..<4 {
                    matrix[column][row] = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + (column * 4 + row) * 4, as: Float.self) }
                }
            }
            return NSValue(scnMatrix4: SCNMatrix4(matrix))
        }
    }

    func instantiate(shirt: UIColor) -> SCNNode {
        let nodes = manifest.nodes.map { joint -> SCNNode in
            let node = SCNNode()
            node.name = joint.name
            node.simdPosition = SIMD3(joint.translation[0], joint.translation[1], joint.translation[2])
            node.simdOrientation = simd_quatf(ix: joint.rotation[0], iy: joint.rotation[1], iz: joint.rotation[2], r: joint.rotation[3])
            node.simdScale = SIMD3(joint.scale[0], joint.scale[1], joint.scale[2])
            return node
        }
        for (index, joint) in manifest.nodes.enumerated() {
            for child in joint.children { nodes[index].addChildNode(nodes[child]) }
        }
        let root = nodes[manifest.root]
        for (index, mesh) in manifest.meshes.enumerated() {
            let geometry = geometries[index].copy() as! SCNGeometry
            let skinMaterial = SCNMaterial()
            skinMaterial.lightingModel = .physicallyBased
            skinMaterial.diffuse.contents = mesh.name.contains("Face.001") ? eyes : mesh.face ? UIColor(white: 0.08, alpha: 1) : skin
            skinMaterial.roughness.contents = mesh.face ? 0.42 : 0.58
            let shirtMaterial = SCNMaterial()
            shirtMaterial.lightingModel = .physicallyBased
            shirtMaterial.diffuse.contents = shirt
            shirtMaterial.roughness.contents = 0.95
            let pants = SCNMaterial()
            pants.lightingModel = .physicallyBased
            pants.diffuse.contents = UIColor(red: 0.17, green: 0.19, blue: 0.17, alpha: 1)
            pants.roughness.contents = 1
            let boots = SCNMaterial()
            boots.lightingModel = .physicallyBased
            boots.diffuse.contents = UIColor(red: 0.14, green: 0.085, blue: 0.055, alpha: 1)
            boots.roughness.contents = 0.8
            geometry.materials = [skinMaterial, shirtMaterial, pants, boots]
            let actor = SCNNode(geometry: geometry)
            actor.name = "humanMesh"
            actor.skinner = SCNSkinner(baseGeometry: geometry, bones: manifest.joints.map { nodes[$0] }, boneInverseBindTransforms: inverseBind, boneWeights: weights[index], boneIndices: indices[index])
            actor.skinner?.skeleton = nodes[64]
            root.addChildNode(actor)
        }
        return root
    }
}

@MainActor
private final class CharacterRig {
    weak var character: SCNNode?
    let skeleton: SCNNode
    let bones: [String: SCNNode]
    let restPositions: [String: SIMD3<Float>]
    let restOrientations: [String: simd_quatf]
    let isGujarat: Bool

    init(character: SCNNode, skeleton: SCNNode) {
        self.character = character
        self.skeleton = skeleton
        isGujarat = skeleton.name?.hasPrefix("gujarat_") == true
        var bones: [String: SCNNode] = [:]
        skeleton.enumerateChildNodes { node, _ in if let name = node.name { bones[name] = node } }
        // Keep the delivered 22-bone names, while sharing the existing two-bone limb solver.
        if isGujarat {
            bones["Head"] = bones["head"]
            for (source, suffix) in [("L", "l"), ("R", "r")] {
                for (canonical, delivered) in [("upperarm", "upper_arm"), ("lowerarm", "forearm"),
                                                ("hand", "hand"), ("thigh", "thigh"),
                                                ("calf", "shin"), ("foot", "foot")] {
                    bones[canonical + "_" + suffix] = bones[delivered + "." + source]
                }
            }
        }
        self.bones = bones
        restPositions = bones.mapValues { skeleton.simdConvertPosition(.zero, from: $0) }
        let inverse = skeleton.simdWorldOrientation.inverse
        restOrientations = bones.mapValues { inverse * $0.simdWorldOrientation }
    }

    func pose(seated: Float, step: Float, breathing: Float) {
        guard let character else { return }
        func point(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            skeleton.simdConvertPosition(SIMD3(x, y, z), from: character)
        }
        let kneeLift = step * 0.22
        for (suffix, side): (String, Float) in [("l", -1), ("r", 1)] {
            let standingAnkle: Float = isGujarat ? -1.05 : -1.12
            let sittingLift: Float = isGujarat ? 0.39 : 0.46
            let foot = point(side * 0.12, standingAnkle + seated * sittingLift + (side < 0 ? kneeLift : 0), -0.05 - seated * 0.39)
            solve(upper: "thigh_" + suffix, lower: "calf_" + suffix, tip: "foot_" + suffix, target: foot, bend: SIMD3(0, 0, 1))
            orient("foot_" + suffix, toward: restOrientations["foot_" + suffix])
            // The new driver's narrow gun grip meets the turret's rear handles at (±.085, 2.04, .69).
            let gripX: Float = isGujarat ? 0.085 + seated * 0.135 : 0.22
            let gripZ: Float = isGujarat ? -0.39 - seated * 0.06 : -0.45
            let grip = point(side * gripX, -0.02 + (1 - seated) * 0.11 + breathing, gripZ)
            solve(upper: "upperarm_" + suffix, lower: "lowerarm_" + suffix, tip: "hand_" + suffix, target: grip, bend: SIMD3(side, -1, 0))
        }
    }

    private func orient(_ name: String, toward orientation: simd_quatf?) {
        guard let bone = bones[name], let parent = bone.parent, let orientation else { return }
        let parentOrientation = skeleton.simdWorldOrientation.inverse * parent.simdWorldOrientation
        bone.simdOrientation = parentOrientation.inverse * orientation
    }

    private func solve(upper: String, lower: String, tip: String, target: SIMD3<Float>, bend: SIMD3<Float>) {
        guard let a = bones[upper], let b = bones[lower], let c = bones[tip],
              let pa = restPositions[upper], let pb = restPositions[lower], let pc = restPositions[tip],
              let qa = restOrientations[upper], let qb = restOrientations[lower] else { return }
        let origin = skeleton.simdConvertPosition(.zero, from: a)
        let lengthA = simd_length(pb - pa), lengthB = simd_length(pc - pb)
        let delta = target - origin
        guard simd_length_squared(delta) > 0.000001 else { return }
        let distance = min(lengthA + lengthB - 0.005, max(0.04, simd_length(delta)))
        let direction = simd_normalize(delta)
        let along = (lengthA * lengthA - lengthB * lengthB + distance * distance) / (2 * distance)
        let height = sqrt(max(0, lengthA * lengthA - along * along))
        var bendAxis = bend - direction * simd_dot(bend, direction)
        if simd_length_squared(bendAxis) < 0.001 { bendAxis = SIMD3(1, 0, 0) }
        let elbow = origin + direction * along + simd_normalize(bendAxis) * height
        let first = simd_quatf(from: simd_normalize(pb - pa), to: simd_normalize(elbow - origin)) * qa
        orient(upper, toward: first)
        let lowerOrigin = skeleton.simdConvertPosition(.zero, from: b)
        let second = simd_quatf(from: simd_normalize(pc - pb), to: simd_normalize(target - lowerOrigin)) * qb
        orient(lower, toward: second)
        _ = c
    }

    /// A crossing step. Left and right swing in opposite directions, with a weight dip.
    func poseWalking(phase: Float) {
        guard let character else { return }
        func point(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            skeleton.simdConvertPosition(SIMD3(x, y, z), from: character)
        }
        skeleton.position.y = -0.016 * abs(cos(phase))
        let swing = sin(phase)
        for (suffix, side): (String, Float) in [("l", 1), ("r", -1)] {
            let step = (suffix == "l" ? 1 : -1) * swing
            let foot = point(side * 0.12, (isGujarat ? 0.13 : 0.02) + max(0, step) * 0.16, 0.04 + step * 0.34)
            solve(upper: "thigh_" + suffix, lower: "calf_" + suffix, tip: "foot_" + suffix, target: foot, bend: SIMD3(0, 0, 1))
            orient("foot_" + suffix, toward: restOrientations["foot_" + suffix])
            let hand = point(side * 0.2, 0.8 - abs(step) * 0.08, -step * 0.28)
            solve(upper: "upperarm_" + suffix, lower: "lowerarm_" + suffix, tip: "hand_" + suffix, target: hand, bend: SIMD3(0, 0, -1))
        }
    }

    /// Arms down and feet planted. Left bones live on +X until the seated yaw flips them.
    func poseStanding() {
        guard let character else { return }
        func point(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            skeleton.simdConvertPosition(SIMD3(x, y, z), from: character)
        }
        for (suffix, side): (String, Float) in [("l", 1), ("r", -1)] {
            let foot = point(side * 0.11, isGujarat ? 0.13 : 0.02, 0.05)
            solve(upper: "thigh_" + suffix, lower: "calf_" + suffix, tip: "foot_" + suffix, target: foot, bend: SIMD3(0, 0, 1))
            orient("foot_" + suffix, toward: restOrientations["foot_" + suffix])
            let hand = point(side * 0.24, 0.72, 0.05)
            solve(upper: "upperarm_" + suffix, lower: "lowerarm_" + suffix, tip: "hand_" + suffix, target: hand, bend: SIMD3(0, 0, -1))
        }
    }
}

/// Curated Kenney OBJ groups, converted to compact interleaved vertex buffers.
@MainActor
private final class ImportedVehicleAsset {
    struct Part: Decodable {
        let name: String
        let offset: Int
        let count: Int
        let position: [Float]
    }
    let parts: [Part]
    let geometries: [SCNGeometry]

    private static func paintMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.metalness.contents = 0.58
        material.roughness.contents = WorldBuilder.texture("gloss")
        material.clearCoat.contents = 1
        material.clearCoatRoughness.contents = 0.04
        return material
    }

    private static func rubberMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.9
        material.metalness.contents = 0.04
        material.shaderModifiers = [.surface: """
        #pragma body
        float luma = dot(_surface.diffuse.rgb, float3(0.3, 0.59, 0.11));
        float metal = smoothstep(0.05, 0.28, luma);
        _surface.roughness = mix(0.94, 0.18, metal);
        _surface.metalness = metal * 0.9;
        """]
        return material
    }

    private static func glassMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.7, green: 0.82, blue: 0.86, alpha: 1)
        material.transparency = 0.32
        material.metalness.contents = 0.08
        material.roughness.contents = 0.02
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.fresnelExponent = 1.6
        return material
    }

    static func load(name: String) -> ImportedVehicleAsset? {
        func resource(_ name: String, _ ext: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Assets") ?? Bundle.main.url(forResource: name, withExtension: ext)
        }
        guard let jsonURL = resource("Vehicle-" + name, "json"), let binaryURL = resource("Vehicle-" + name, "bin"),
              let colorsURL = resource("Vehicle-" + name + "-colors", "bin"), let colors = try? Data(contentsOf: colorsURL),
              let json = try? Data(contentsOf: jsonURL), let data = try? Data(contentsOf: binaryURL),
              let parts = try? JSONDecoder().decode([Part].self, from: json) else { return nil }
        return ImportedVehicleAsset(parts: parts, data: data, colors: colors)
    }

    private init(parts: [Part], data: Data, colors: Data) {
        self.parts = parts
        let paint = Self.paintMaterial()
        let rubber = Self.rubberMaterial()
        let glass = Self.glassMaterial()
        geometries = parts.map { part in
            let packed = data.subdata(in: part.offset..<(part.offset + part.count * 32))
            func source(_ semantic: SCNGeometrySource.Semantic, offset: Int, components: Int) -> SCNGeometrySource {
                SCNGeometrySource(data: packed, semantic: semantic, vectorCount: part.count, usesFloatComponents: true,
                                  componentsPerVector: components, bytesPerComponent: 4, dataOffset: offset, dataStride: 32)
            }
            let element = SCNGeometryElement(data: nil, primitiveType: .triangles, primitiveCount: part.count / 3, bytesPerIndex: 0)
            let colorOffset = part.offset / 2
            let colorData = colors.subdata(in: colorOffset..<(colorOffset + part.count * 16))
            let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: part.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let geometry = SCNGeometry(sources: [source(.vertex, offset: 0, components: 3), source(.normal, offset: 12, components: 3), source(.texcoord, offset: 24, components: 2), colorSource], elements: [element])
            geometry.firstMaterial = part.name == "glass" ? glass : part.name.hasPrefix("wheel") ? rubber : paint
            return geometry
        }
    }

    func instantiate() -> SCNNode {
        let root = ImportedVehicleNode()
        for (index, part) in parts.enumerated() {
            let node = SCNNode(geometry: geometries[index])
            node.position = SCNVector3(part.position[0], part.position[1], part.position[2])
            if part.name.hasPrefix("wheel-") && part.name != "wheel-back" {
                node.name = "wheel"
            } else if part.name == "glass" {
                node.name = "vehicleGlass"
            } else {
                node.name = part.name == "body" ? "importedVehicleMesh" : "importedSpareTire"
            }
            root.addChildNode(node)
        }
        return root
    }
}

private final class ImportedVehicleNode: SCNNode {
    let rideHeight: Float = 0.42
}

private final class VehicleMotion {
    var previousTime: Float?
    var previousSpeed: Float = 0
    var spin: Float = 0
    var lean: Float = 0
    var pitch: Float = 0
}

/// Vertex-colored shell for the player jeep. Wheels, lights and the gun stay separate.
private enum SculptedMesh {
    static func load(_ resource: String) -> SCNNode? {
        func url(_ ext: String) -> URL? {
            Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Assets")
                ?? Bundle.main.url(forResource: resource, withExtension: ext)
        }
        guard let jsonURL = url("json"), let binaryURL = url("bin"),
              let raw = try? JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any],
              let count = (raw["count"] as? Int) ?? (raw["count"] as? NSNumber)?.intValue,
              count > 0, count.isMultiple(of: 3),
              let data = try? Data(contentsOf: binaryURL), data.count == count * 40 else { return nil }
        func source(_ semantic: SCNGeometrySource.Semantic, offset: Int, components: Int) -> SCNGeometrySource {
            SCNGeometrySource(data: data, semantic: semantic, vectorCount: count, usesFloatComponents: true,
                              componentsPerVector: components, bytesPerComponent: 4, dataOffset: offset, dataStride: 40)
        }
        let element = SCNGeometryElement(data: nil, primitiveType: .triangles, primitiveCount: count / 3, bytesPerIndex: 0)
        let geometry = SCNGeometry(sources: [source(.vertex, offset: 0, components: 3), source(.normal, offset: 12, components: 3), source(.color, offset: 24, components: 4)], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.55
        material.metalness.contents = 0.2
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }
}

/// Modeled town shells. Window faces stay a separate mesh so they can glow at night.
@MainActor
private final class ImportedEnvironmentAsset {
    struct Part: Decodable { let name: String; let offset: Int; let count: Int }
    struct Model: Decodable { let name: String; let parts: [Part]; let bounds: [[Float]] }
    let models: [String: Model]
    let geometries: [String: [SCNGeometry]]

    static func load() -> ImportedEnvironmentAsset? {
        func resource(_ ext: String) -> URL? {
            Bundle.main.url(forResource: "EnvironmentMesh", withExtension: ext, subdirectory: "Assets") ?? Bundle.main.url(forResource: "EnvironmentMesh", withExtension: ext)
        }
        guard let jsonURL = resource("json"), let binaryURL = resource("bin"),
              let json = try? Data(contentsOf: jsonURL), let data = try? Data(contentsOf: binaryURL),
              let models = try? JSONDecoder().decode([Model].self, from: json) else { return nil }
        return ImportedEnvironmentAsset(models: models, data: data)
    }

    private init(models: [Model], data: Data) {
        self.models = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })
        geometries = Dictionary(uniqueKeysWithValues: models.map { model in
            let parts = model.parts.map { part -> SCNGeometry in
                let packed = data.subdata(in: part.offset..<(part.offset + part.count * 40))
                func source(_ semantic: SCNGeometrySource.Semantic, offset: Int, components: Int) -> SCNGeometrySource {
                    SCNGeometrySource(data: packed, semantic: semantic, vectorCount: part.count, usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: 4, dataOffset: offset, dataStride: 40)
                }
                let element = SCNGeometryElement(data: nil, primitiveType: .triangles, primitiveCount: part.count / 3, bytesPerIndex: 0)
                var sources = [
                    source(.vertex, offset: 0, components: 3),
                    source(.normal, offset: 12, components: 3),
                    source(.color, offset: 24, components: 4)
                ]
                if part.name != "window" {
                    sources.append(SCNGeometrySource(textureCoordinates: [CGPoint](repeating: .zero, count: part.count)))
                }
                let geometry = SCNGeometry(sources: sources, elements: [element])
                let kind = model.name.hasPrefix("fence") ? "wood" : model.name == "rock" ? "sand" : "plaster"
                geometry.firstMaterial = part.name == "window" ? WorldBuilder.windowGlass() : WorldBuilder.sceneryMaterial(kind)
                return geometry
            }
            return (model.name, parts)
        })
    }

    func instantiate(name: String) -> SCNNode? {
        guard let model = models[name], let parts = geometries[name] else { return nil }
        let root = SCNNode()
        root.name = "importedEnvironment"
        for (index, part) in model.parts.enumerated() {
            let node = SCNNode(geometry: parts[index])
            node.name = part.name == "window" ? "litWindow" : "importedBuildingMesh"
            root.addChildNode(node)
        }
        let low = model.bounds[0], high = model.bounds[1]
        root.boundingBox = (SCNVector3(low[0], low[1], low[2]), SCNVector3(high[0], high[1], high[2]))
        return root
    }
}
