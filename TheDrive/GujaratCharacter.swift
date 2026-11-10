import SceneKit
import UIKit
import simd

enum GujaratCharacter: String, CaseIterable {
    case driver, explorer, grandpa
}

/// Optimized versions of the supplied Gujarat character pack retain their source rigs and wardrobe.
@MainActor
final class GujaratCharacterAsset {
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
        let materialIndices: [Int]
    }
    struct Material: Decodable {
        let name: String
        let baseColor: [Float]
        let metallic: Float
        let roughness: Float
        let baseColorTexture: String?
        let normalTexture: String?
        let metallicRoughnessTexture: String?
        let alphaMode: String?
        let alphaCutoff: Float?
        let doubleSided: Bool?
    }
    struct Manifest: Decodable {
        let nodes: [Joint]
        let joints: [Int]
        let inverseBind: Slice
        let meshes: [Mesh]
        let materials: [Material]
        let root: Int
    }

    private static var assets: [GujaratCharacter: GujaratCharacterAsset] = [:]
    private static var attempted = Set<GujaratCharacter>()
    private let kind: GujaratCharacter
    private let manifest: Manifest
    private let geometries: [SCNGeometry]
    private let weights: [SCNGeometrySource]
    private let indices: [SCNGeometrySource]
    private let inverseBind: [NSValue]
    private let materials: [SCNMaterial]

    static func load(_ kind: GujaratCharacter) -> GujaratCharacterAsset? {
        if let asset = assets[kind] { return asset }
        guard attempted.insert(kind).inserted else { return nil }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Assets/Gujarat"),
              let json = try? Data(contentsOf: directory.appendingPathComponent("\(kind.rawValue).json")),
              let data = try? Data(contentsOf: directory.appendingPathComponent("\(kind.rawValue).bin")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: json),
              valid(manifest, bytes: data.count) else {
            return nil
        }
        let asset = GujaratCharacterAsset(kind: kind, manifest: manifest, data: data, directory: directory)
        assets[kind] = asset
        return asset
    }

    private static func valid(_ manifest: Manifest, bytes: Int) -> Bool {
        func slice(_ value: Slice, stride: Int) -> Bool {
            value.offset >= 0 && value.count > 0 && value.offset <= bytes
                && value.count <= (bytes - value.offset) / stride
        }
        guard manifest.nodes.indices.contains(manifest.root), !manifest.joints.isEmpty,
              manifest.joints.allSatisfy({ manifest.nodes.indices.contains($0) }),
              manifest.joints.count == manifest.inverseBind.count,
              slice(manifest.inverseBind, stride: 64), !manifest.meshes.isEmpty else { return false }
        for node in manifest.nodes {
            guard node.translation.count == 3, node.rotation.count == 4, node.scale.count == 3,
                  (node.translation + node.rotation + node.scale).allSatisfy(\.isFinite),
                  node.children.allSatisfy({ manifest.nodes.indices.contains($0) }) else { return false }
        }
        for mesh in manifest.meshes {
            guard slice(mesh.positions, stride: 12), slice(mesh.normals, stride: 12),
                  slice(mesh.uv, stride: 8), slice(mesh.joints, stride: 8), slice(mesh.weights, stride: 16),
                  mesh.positions.count == mesh.normals.count, mesh.positions.count == mesh.uv.count,
                  mesh.positions.count == mesh.joints.count, mesh.positions.count == mesh.weights.count,
                  mesh.triangles.count == mesh.materialIndices.count,
                  mesh.materialIndices.allSatisfy({ manifest.materials.indices.contains($0) }),
                  mesh.triangles.allSatisfy({ slice($0, stride: 4) && $0.count % 3 == 0 }) else { return false }
        }
        return manifest.materials.allSatisfy { $0.baseColor.count == 4 }
    }

    private init(kind: GujaratCharacter, manifest: Manifest, data: Data, directory: URL) {
        self.kind = kind
        self.manifest = manifest
        func source(_ slice: Slice, _ semantic: SCNGeometrySource.Semantic,
                    components: Int, bytes: Int = 4, floats: Bool = true) -> SCNGeometrySource {
            let packed = data.subdata(in: slice.offset..<(slice.offset + slice.count * components * bytes))
            return SCNGeometrySource(data: packed, semantic: semantic, vectorCount: slice.count,
                                     usesFloatComponents: floats, componentsPerVector: components,
                                     bytesPerComponent: bytes, dataOffset: 0, dataStride: components * bytes)
        }
        geometries = manifest.meshes.map { mesh in
            let elements = mesh.triangles.map { slice in
                SCNGeometryElement(data: data.subdata(in: slice.offset..<(slice.offset + slice.count * 4)),
                                   primitiveType: .triangles, primitiveCount: slice.count / 3, bytesPerIndex: 4)
            }
            return SCNGeometry(sources: [source(mesh.positions, .vertex, components: 3),
                                        source(mesh.normals, .normal, components: 3),
                                        source(mesh.uv, .texcoord, components: 2)], elements: elements)
        }
        weights = manifest.meshes.map { source($0.weights, .boneWeights, components: 4) }
        indices = manifest.meshes.map { source($0.joints, .boneIndices, components: 4, bytes: 2, floats: false) }
        inverseBind = (0..<manifest.inverseBind.count).map { index in
            let offset = manifest.inverseBind.offset + index * 64
            var matrix = matrix_identity_float4x4
            for column in 0..<4 {
                for row in 0..<4 {
                    matrix[column][row] = data.withUnsafeBytes {
                        $0.loadUnaligned(fromByteOffset: offset + (column * 4 + row) * 4, as: Float.self)
                    }
                }
            }
            return NSValue(scnMatrix4: SCNMatrix4(matrix))
        }
        var textures: [String: UIImage] = [:]
        func texture(_ name: String?) -> UIImage? {
            guard let name else { return nil }
            if let image = textures[name] { return image }
            guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
            textures[name] = image
            return image
        }
        materials = manifest.materials.map { source in
            let material = SCNMaterial()
            material.name = source.name
            material.lightingModel = .physicallyBased
            let components = source.baseColor.map(CGFloat.init)
            let color = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!, components: components)!
            if let image = texture(source.baseColorTexture) {
                material.diffuse.contents = image
                material.multiply.contents = UIColor(cgColor: color)
            } else { material.diffuse.contents = UIColor(cgColor: color) }
            material.roughness.contents = source.roughness
            material.metalness.contents = source.metallic
            if let packed = texture(source.metallicRoughnessTexture) {
                material.roughness.contents = packed
                material.roughness.textureComponents = .green
                material.metalness.contents = packed
                material.metalness.textureComponents = .blue
            }
            if let normal = texture(source.normalTexture) { material.normal.contents = normal }
            material.isDoubleSided = source.doubleSided ?? false
            if source.alphaMode == "BLEND" {
                material.transparencyMode = .aOne
                material.writesToDepthBuffer = false
            }
            for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
                property.wrapS = .repeat
                property.wrapT = .repeat
                // Packed UVs use Blender's bottom-origin convention; UIImage-backed SceneKit maps use image rows.
                var atlasTransform = SCNMatrix4MakeScale(1, -1, 1)
                atlasTransform.m42 = 1
                property.contentsTransform = atlasTransform
            }
            return material
        }
    }

    /// The returned root is Y-up and faces +Z, matching the existing standing-character convention.
    func instantiate() -> SCNNode {
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
        root.name = "gujarat_\(kind.rawValue)"
        let goggles = SCNNode()
        goggles.name = "sunglasses"
        for (index, mesh) in manifest.meshes.enumerated() {
            let geometry = geometries[index].copy() as! SCNGeometry
            geometry.materials = mesh.materialIndices.map { materials[$0].copy() as! SCNMaterial }
            let actor = SCNNode(geometry: geometry)
            let lens = mesh.name == "sunglassLens" || mesh.name.lowercased().contains("smoked_lens")
            let eyewear = lens || mesh.name == "sunglasses" || mesh.name.lowercased().contains("goggle")
            actor.name = lens ? "sunglassLens" : eyewear ? "goggleFrame" : "humanMesh"
            actor.skinner = SCNSkinner(baseGeometry: geometry,
                                      bones: manifest.joints.map { nodes[$0] },
                                      boneInverseBindTransforms: inverseBind,
                                      boneWeights: weights[index], boneIndices: indices[index])
            actor.skinner?.skeleton = root
            // A conservative bound includes bent knees and hands during transfers, avoiding skin culling.
            actor.boundingBox = (SCNVector3(-0.85, -0.15, -0.85), SCNVector3(0.85, 2.15, 0.85))
            if eyewear {
                if lens { actor.categoryBitMask = 2 }
                goggles.addChildNode(actor)
            } else { root.addChildNode(actor) }
        }
        if !goggles.childNodes.isEmpty { root.addChildNode(goggles) }
        return root
    }
}
