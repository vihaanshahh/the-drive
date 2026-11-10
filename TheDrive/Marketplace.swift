import SceneKit
import UIKit
import simd

/// A small, seeded roadside bazaar for the opening drive. The running lane stays clear.
@MainActor
enum Marketplace {
    private static let wood = UIColor(red: 0.32, green: 0.19, blue: 0.10, alpha: 1)
    private static let lightWood = UIColor(red: 0.57, green: 0.35, blue: 0.17, alpha: 1)
    private static let cream = UIColor(red: 0.98, green: 0.86, blue: 0.62, alpha: 1)
    private static let metal = UIColor(red: 0.16, green: 0.20, blue: 0.19, alpha: 1)
    private static let colors: [UIColor] = [
        UIColor(red: 0.80, green: 0.20, blue: 0.13, alpha: 1),
        UIColor(red: 0.10, green: 0.47, blue: 0.45, alpha: 1),
        UIColor(red: 0.92, green: 0.57, blue: 0.10, alpha: 1),
        UIColor(red: 0.52, green: 0.24, blue: 0.42, alpha: 1),
        UIColor(red: 0.26, green: 0.40, blue: 0.60, alpha: 1)
    ]
    private static var materials: [String: SCNMaterial] = [:]
    private static var signs: [String: SCNMaterial] = [:]

    /// World coordinates match the first road tiles: forward is -Z, road distance is -z.
    static func make(seed: UInt64) -> SCNNode {
        let root = SCNNode()
        root.name = "openingMarketplace"
        var random = BazaarRandom(state: seed ^ 0xBA2AA7)
        let labels = ["FRESH FRUIT", "CHAI & LASSI", "SPICE MERCHANT", "HANDWOVEN", "SADAR STORES"]
        for side: Float in [-1, 1] {
            for row in 0..<7 {
                let z = 14 - Float(row) * 16 + random.range(-1.3, 1.3)
                let x = side * random.range(7.8, 8.15)
                let base = RoadSurface.height(distance: -Double(z), x: x, seed: seed)
                let color = Int(random.next() % UInt64(colors.count))
                let kind = (row + (side < 0 ? 0 : 2)) % labels.count
                let stall = makeStall(side: side, color: color, kind: kind, label: labels[kind], random: &random)
                stall.position = SCNVector3(x, base + 0.035, z)
                stall.name = "marketStall"
                root.addChildNode(stall)

                if row == 0 || row == 2 {
                    let vendorX = x + side * 0.25
                    let vendorZ = z + 1.25
                    let vendorY = RoadSurface.height(distance: -Double(vendorZ), x: vendorX, seed: seed)
                    root.addChildNode(makePerson(index: root.childNodes.count, color: color,
                                                 position: SCNVector3(vendorX, vendorY, vendorZ),
                                                 yaw: -side * .pi / 2 + random.range(-0.25, 0.25)))
                    let shopperX = side * random.range(6.25, 6.55)
                    let shopperZ = z - 0.6
                    let shopperY = RoadSurface.height(distance: -Double(shopperZ), x: shopperX, seed: seed)
                    root.addChildNode(makePerson(index: root.childNodes.count, color: (color + 2) % colors.count,
                                                 position: SCNVector3(shopperX, shopperY, shopperZ),
                                                 yaw: side * .pi / 2 + random.range(-0.3, 0.3)))
                }
            }
        }

        for (index, z): (Int, Float) in [(0, 4), (1, -28), (2, -60), (3, -91)] {
            root.addChildNode(makeBunting(z: z, index: index, seed: seed))
        }
        let gateway = SCNNode()
        let gateZ: Float = -9
        let gateY = RoadSurface.height(distance: -Double(gateZ), x: 0, seed: seed)
        for x: Float in [-6.3, 6.3] {
            gateway.addChildNode(cylinder(radius: 0.10, height: 5.8, material: material("wood", wood),
                                          at: SCNVector3(x, gateY + 2.9, gateZ)))
        }
        gateway.addChildNode(box(12.8, 0.15, 0.17, material("wood", wood), at: SCNVector3(0, gateY + 5.65, gateZ)))
        gateway.addChildNode(sign("SADAR BAZAAR", width: 5.8, height: 0.72,
                                  at: SCNVector3(0, gateY + 5.30, gateZ + 0.02)))
        let gateMesh = flattened(gateway)
        gateMesh.name = "marketGateway"
        root.addChildNode(gateMesh)
        return root
    }

    /// Small movements are sampled from the caller's simulation clock, so pausing freezes them.
    static func animate(in root: SCNNode, time: Float) {
        guard time.isFinite else { return }
        for (index, node) in root.childNodes.enumerated() where node.name?.hasPrefix("marketPerson") == true {
            node.eulerAngles.y = sin(time * 0.65 + Float(index) * 1.7) * 0.075
            node.eulerAngles.z = sin(time * 1.1 + Float(index)) * 0.008
        }
    }

    private static func makeStall(side: Float, color: Int, kind: Int, label: String,
                                  random: inout BazaarRandom) -> SCNNode {
        let root = SCNNode()
        let darkWood = material("wood", wood)
        let timber = material("lightWood", lightWood)
        let cloth = material("cloth\(color)", colors[color])
        let pale = material("cream", cream)
        let iron = material("metal", metal)
        root.addChildNode(box(3.3, 0.11, 5.5, timber, at: SCNVector3(0, 0.025, 0)))
        for x: Float in [-1.4, 1.4] {
            for z: Float in [-2.45, 2.45] {
                let height: Float = x * side < 0 ? 2.65 : 3.15
                root.addChildNode(cylinder(radius: 0.055, height: height, material: darkWood,
                                          at: SCNVector3(x, height / 2, z)))
            }
        }
        let canopyColor = [cloth, pale]
        for stripe in 0..<12 {
            let z0 = -2.7 + Float(stripe) * 0.45
            let vertices = [SCNVector3(-1.65, 2.92 - side * 0.30, z0),
                            SCNVector3(1.65, 2.92 + side * 0.30, z0),
                            SCNVector3(-1.65, 2.92 - side * 0.30, z0 + 0.45),
                            SCNVector3(1.65, 2.92 + side * 0.30, z0 + 0.45)]
            let canvas = mesh(vertices, indices: [0, 2, 1, 1, 2, 3], material: canopyColor[stripe % 2])
            root.addChildNode(canvas)
            let edgeX = -side * 1.65
            let edgeY: Float = 2.62
            let scallop = [SCNVector3(edgeX, edgeY, z0), SCNVector3(edgeX, edgeY, z0 + 0.45),
                           SCNVector3(edgeX, edgeY - 0.18, z0 + 0.225)]
            root.addChildNode(mesh(scallop, indices: [0, 1, 2], material: canopyColor[stripe % 2]))
        }
        root.addChildNode(box(0.12, 0.12, 5.5, darkWood, at: SCNVector3(-side * 1.57, 2.64, 0)))
        let frontX = -side * 1.16
        root.addChildNode(box(0.76, 0.64, 4.5, timber, at: SCNVector3(frontX, 0.89, 0)))
        root.addChildNode(box(0.84, 0.09, 4.65, darkWood, at: SCNVector3(frontX, 1.25, 0)))
        for z: Float in [-1.8, 1.8] {
            root.addChildNode(box(0.10, 0.55, 0.10, darkWood, at: SCNVector3(frontX, 0.32, z)))
        }
        let stallSign = sign(label, width: 3.0, height: 0.45, at: SCNVector3(-side * 1.62, 2.20, 0))
        stallSign.eulerAngles.y = -side * .pi / 2
        root.addChildNode(stallSign)

        if kind == 1 {
            // A road-facing tea counter with kettle, metal cups and a clay pot.
            for z: Float in [-0.7, 0.65] {
                root.addChildNode(cylinder(radius: 0.24, height: 0.39, material: iron,
                                          at: SCNVector3(frontX, 1.48, z)))
                root.addChildNode(cylinder(radius: 0.26, height: 0.05, material: pale,
                                          at: SCNVector3(frontX, 1.70, z)))
            }
            for z: Float in [-1.65, -1.35, -1.05, 1.05, 1.35, 1.65] {
                root.addChildNode(cylinder(radius: 0.07, height: 0.12, material: pale,
                                          at: SCNVector3(frontX - side * 0.2, 1.36, z)))
            }
        } else if kind == 3 {
            // Folded cloth and a hanging rug give the row a different silhouette.
            for (index, z): (Int, Float) in [(0, -1.4), (1, 0), (2, 1.4)] {
                for layer in 0..<4 {
                    root.addChildNode(box(0.62, 0.08, 0.9, material("cloth\((color + index + layer) % colors.count)", colors[(color + index + layer) % colors.count]),
                                          at: SCNVector3(frontX, 1.34 + Float(layer) * 0.08, z)))
                }
            }
            let rug = box(0.035, 1.7, 1.45, cloth, at: SCNVector3(side * 1.3, 1.5, -1.1))
            root.addChildNode(rug)
            for y: Float in [0.8, 0.95, 2.05, 2.2] {
                root.addChildNode(box(0.045, 0.065, 1.4, pale, at: SCNVector3(side * 1.27, y, -1.1)))
            }
        } else {
            for tray in 0..<4 {
                let z = -1.7 + Float(tray) * 1.12
                root.addChildNode(box(0.74, 0.10, 1.02, darkWood, at: SCNVector3(frontX, 1.35, z)))
                let produceColor: UIColor
                switch (tray + kind) % 4 {
                case 0: produceColor = UIColor(red: 0.86, green: 0.19, blue: 0.10, alpha: 1)
                case 1: produceColor = UIColor(red: 0.94, green: 0.64, blue: 0.13, alpha: 1)
                case 2: produceColor = UIColor(red: 0.30, green: 0.52, blue: 0.17, alpha: 1)
                default: produceColor = UIColor(red: 0.68, green: 0.31, blue: 0.09, alpha: 1)
                }
                let fruitMaterial = material("produce\((tray + kind) % 4)", produceColor)
                for fruit in 0..<8 {
                    let sphere = SCNSphere(radius: kind == 2 ? 0.15 : 0.105)
                    sphere.segmentCount = 8
                    sphere.firstMaterial = fruitMaterial
                    let node = SCNNode(geometry: sphere)
                    node.position = SCNVector3(frontX + Float(fruit % 2) * 0.26 - 0.13 + random.range(-0.03, 0.03),
                                               1.48 + random.range(0, 0.07),
                                               z + Float(fruit / 2) * 0.22 - 0.33)
                    if kind == 2 { node.scale = SCNVector3(1, 0.45, 1) }
                    root.addChildNode(node)
                }
            }
        }
        for (index, z): (Int, Float) in [(0, -2), (1, 2)] {
            let crateX: Float = side * 0.5
            root.addChildNode(box(0.65, 0.5, 0.7, timber, at: SCNVector3(crateX, 0.35, z)))
            for y: Float in [0.19, 0.39, 0.59] {
                root.addChildNode(box(0.68, 0.045, 0.74, darkWood, at: SCNVector3(crateX, y, z)))
            }
            if index == 0 {
                let pot = SCNSphere(radius: 0.32)
                pot.segmentCount = 12
                pot.firstMaterial = material("terracotta", UIColor(red: 0.59, green: 0.27, blue: 0.13, alpha: 1))
                let node = SCNNode(geometry: pot)
                node.scale = SCNVector3(1, 1.25, 1)
                node.position = SCNVector3(crateX, 1.0, z)
                root.addChildNode(node)
            }
        }
        // One static draw group per stall, with shared opaque materials across all stalls.
        return flattened(root)
    }

    private static func makePerson(index: Int, color: Int, position: SCNVector3, yaw: Float) -> SCNNode {
        let wrapper = SCNNode()
        wrapper.name = "marketPerson\(index)"
        wrapper.position = position
        let identity: GujaratCharacter = index.isMultiple(of: 2) ? .grandpa : .explorer
        let person = WorldBuilder.makePedestrian(character: identity)
        person.eulerAngles.y = yaw
        let suppliedCharacter = person.childNode(withName: "gujarat_\(identity.rawValue)", recursively: true) != nil
        var imported = false
        person.enumerateChildNodes { node, _ in
            if !suppliedCharacter, node.name == "humanMesh", let geometry = node.geometry, geometry.materials.count > 1 {
                imported = true
                let shirt = geometry.materials[1].copy() as! SCNMaterial
                shirt.diffuse.contents = colors[color]
                geometry.materials[1] = shirt
            }
        }
        if !suppliedCharacter, !imported, let torso = person.childNodes.first?.geometry,
           let shirt = torso.firstMaterial?.copy() as? SCNMaterial {
            shirt.diffuse.contents = colors[color]
            torso.firstMaterial = shirt
        }
        wrapper.addChildNode(person)
        return wrapper
    }

    private static func makeBunting(z: Float, index: Int, seed: UInt64) -> SCNNode {
        let root = SCNNode()
        let base = RoadSurface.height(distance: -Double(z), x: 0, seed: seed)
        for side: Float in [-1, 1] {
            root.addChildNode(cylinder(radius: 0.05, height: 5.8, material: material("wood", wood),
                                      at: SCNVector3(side * 6.3, base + 2.9, z)))
        }
        for flag in 0..<25 {
            let x = -6.15 + Float(flag) * 0.5
            let y = base + 5.75 - 0.7 * (1 - pow(x / 6.3, 2))
            let nextX = x + 0.5
            let nextY = base + 5.75 - 0.7 * (1 - pow(nextX / 6.3, 2))
            root.addChildNode(mesh([SCNVector3(x, y, z), SCNVector3(nextX, nextY, z),
                                    SCNVector3(x + 0.25, (y + nextY) / 2 - 0.45, z + 0.07)],
                                  indices: [0, 1, 2], material: material("cloth\((flag + index) % colors.count)", colors[(flag + index) % colors.count])))
        }
        let result = flattened(root)
        result.name = "marketBunting"
        return result
    }

    private static func material(_ key: String, _ color: UIColor) -> SCNMaterial {
        if let cached = materials[key] { return cached }
        let result = SCNMaterial()
        result.lightingModel = .physicallyBased
        result.diffuse.contents = color
        result.roughness.contents = 0.9
        result.isDoubleSided = true
        materials[key] = result
        return result
    }

    private static func sign(_ title: String, width: Float, height: Float, at position: SCNVector3) -> SCNNode {
        let board = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        if let cached = signs[title] { board.firstMaterial = cached }
        else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 100), format: format).image { renderer in
                let context = renderer.cgContext
                UIColor(red: 0.14, green: 0.30, blue: 0.28, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 640, height: 100))
                cream.setStroke()
                context.setLineWidth(3)
                context.stroke(CGRect(x: 7, y: 7, width: 626, height: 86))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 39, weight: .heavy),
                    .foregroundColor: cream,
                    .paragraphStyle: paragraph,
                    .kern: 3
                ]
                (title as NSString).draw(in: CGRect(x: 15, y: 26, width: 610, height: 55), withAttributes: attributes)
            }
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.9
            material.isDoubleSided = true
            signs[title] = material
            board.firstMaterial = material
        }
        let node = SCNNode(geometry: board)
        node.position = position
        return node
    }

    private static func mesh(_ positions: [SCNVector3], indices: [Int32], material: SCNMaterial) -> SCNNode {
        let source = SCNGeometrySource(vertices: positions)
        let first = positions[Int(indices[0])]
        let second = positions[Int(indices[1])]
        let third = positions[Int(indices[2])]
        let a = SIMD3(second.x - first.x, second.y - first.y, second.z - first.z)
        let b = SIMD3(third.x - first.x, third.y - first.y, third.z - first.z)
        let direction = simd_normalize(simd_cross(a, b))
        let normal = SCNVector3(direction.x, direction.y, direction.z)
        let normals = SCNGeometrySource(normals: Array(repeating: normal, count: positions.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source, normals], elements: [element])
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private static func box(_ width: Float, _ height: Float, _ length: Float,
                            _ material: SCNMaterial, at position: SCNVector3) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.015)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private static func cylinder(radius: Float, height: Float, material: SCNMaterial, at position: SCNVector3) -> SCNNode {
        let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
        geometry.radialSegmentCount = 10
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    /// Preserve all grouping transforms before SceneKit merges primitive meshes lazily.
    private static func flattened(_ root: SCNNode) -> SCNNode {
        let batch = SCNNode()
        var leaves: [(SCNNode, simd_float4x4)] = []
        let inverse = root.simdWorldTransform.inverse
        root.enumerateChildNodes { node, _ in
            if node.geometry != nil { leaves.append((node, inverse * node.simdWorldTransform)) }
        }
        for (node, transform) in leaves {
            node.removeFromParentNode()
            batch.addChildNode(node)
            node.simdTransform = transform
        }
        let bounds = batch.boundingBox
        let result = batch.flattenedClone()
        result.boundingBox = bounds
        return result
    }
}

private struct BazaarRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + Float(Double(next() >> 11) / 9_007_199_254_740_992) * (upper - lower)
    }
}
