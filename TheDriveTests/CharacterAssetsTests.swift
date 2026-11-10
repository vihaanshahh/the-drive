import XCTest
import SceneKit
import UIKit
import simd
@testable import TheDrive

@MainActor
final class CharacterAssetsTests: XCTestCase {
    func testSuppliedCastLoadsWithoutFallbackAndFitsMobileGeometryBudget() throws {
        for identity in GujaratCharacter.allCases {
            XCTAssertNotNil(GujaratCharacterAsset.load(identity), "The actual \(identity.rawValue) bundle must decode.")
            let person = WorldBuilder.makePedestrian(character: identity)
            let supplied = try XCTUnwrap(person.childNode(withName: "gujarat_\(identity.rawValue)", recursively: true))
            XCTAssertNil(person.childNode(withName: "groom", recursively: true), "Keep each supplied hairstyle and clean-shaven face.")
            let meshes = skinnedMeshes(in: supplied)
            XCTAssertFalse(meshes.isEmpty)
            var triangleCount = 0
            for actor in meshes {
                let skin = try XCTUnwrap(actor.skinner)
                XCTAssertEqual(skin.bones.count, 22)
                XCTAssertEqual(skin.boneInverseBindTransforms?.count, 22)
                XCTAssertTrue(skin.bones.contains { $0.name == "head" })
                XCTAssertTrue(skin.bones.contains { $0.name == "forearm.L" })
                for bone in skin.bones { XCTAssertTrue(finite(bone.simdWorldTransform)) }
                let geometry = try XCTUnwrap(actor.geometry)
                triangleCount += geometry.elements.reduce(0) { $0 + ($1.primitiveType == .triangles ? $1.primitiveCount : 0) }
                let points = try skinSamples(actor)
                XCTAssertFalse(points.isEmpty)
                XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                XCTAssertTrue(points.allSatisfy { abs($0.x) < 1 && $0.y > -0.2 && $0.y < 2.3 && abs($0.z) < 1 },
                              "Standing skinned geometry must remain near its skeleton.")
            }
            XCTAssertGreaterThan(triangleCount, 1_000)
            XCTAssertLessThanOrEqual(triangleCount, 50_000, "Presentation meshes need the actual mobile optimization pass.")
            let body = try XCTUnwrap(meshes.first { $0.name == "humanMesh" })
            let material = try XCTUnwrap(body.geometry?.firstMaterial)
            for (label, value) in [("color", material.diffuse.contents), ("normal", material.normal.contents),
                                    ("roughness", material.roughness.contents), ("metallic", material.metalness.contents)] {
                let image = try XCTUnwrap(value as? UIImage, "\(identity.rawValue)'s \(label) PBR atlas must be bundled and loaded.")
                let pixels = try XCTUnwrap(image.cgImage)
                XCTAssertLessThanOrEqual(pixels.width, 1024)
                XCTAssertLessThanOrEqual(pixels.height, 1024)
                XCTAssertGreaterThan(pixels.width, 128)
            }
        }
    }

    func testSourceGogglesFollowHeadAndSupplyBothReflectionLenses() throws {
        let jeep = WorldBuilder.makeJeep()
        let driver = try XCTUnwrap(jeep.childNode(withName: "playerDriver", recursively: true))
        let goggles = try XCTUnwrap(driver.childNode(withName: "sunglasses", recursively: true))
        let lenses = goggles.childNodes.filter { $0.name == "sunglassLens" }
        XCTAssertEqual(lenses.count, 2, "Use the supplied goggles, with separate live-reflection surfaces.")
        for lens in lenses {
            XCTAssertEqual(lens.categoryBitMask, 2)
            let skin = try XCTUnwrap(lens.skinner)
            let head = try XCTUnwrap(skin.bones.firstIndex { $0.name == "head" })
            let weights = skin.boneWeights
            let joints = skin.boneIndices
            for vertex in stride(from: 0, to: weights.vectorCount, by: max(1, weights.vectorCount / 17)) {
                let w = values(weights, at: vertex)
                let j = values(joints, at: vertex)
                for component in 0..<min(4, w.count) where w[component] > 0.001 {
                    XCTAssertEqual(Int(j[component]), head)
                }
            }
        }
        WorldBuilder.setNight(true, in: jeep)
        XCTAssertTrue(goggles.isHidden)
        WorldBuilder.setNight(false, in: jeep)
        XCTAssertFalse(goggles.isHidden)
    }

    func testPackedAtlasCoordinatesSampleFaceAndClothesInsteadOfEmptyTexels() throws {
        for identity in GujaratCharacter.allCases {
            let person = WorldBuilder.makePedestrian(character: identity)
            let body = try XCTUnwrap(skinnedMeshes(in: person).first { $0.name == "humanMesh" })
            let geometry = try XCTUnwrap(body.geometry)
            let material = try XCTUnwrap(geometry.firstMaterial)
            let image = try XCTUnwrap((material.diffuse.contents as? UIImage)?.cgImage)
            let positions = try XCTUnwrap(geometry.sources(for: .vertex).first)
            let coordinates = try XCTUnwrap(geometry.sources(for: .texcoord).first)
            for property in [material.diffuse, material.normal, material.roughness, material.metalness] {
                XCTAssertEqual(property.contentsTransform.m22, -1, accuracy: 0.0001)
                XCTAssertEqual(property.contentsTransform.m42, 1, accuracy: 0.0001)
            }
            let targets: [SIMD3<Float>] = [SIMD3(0.06, 1.62, 0.085), SIMD3(0.13, 1.20, 0.12), SIMD3(0.10, 0.58, 0.09)]
            for (landmark, target) in targets.enumerated() {
                let index = nearestVertex(in: positions, to: target)
                let uv = values(coordinates, at: index)
                let transform = material.diffuse.contentsTransform
                let u = transform.m11 * uv[0] + transform.m21 * uv[1] + transform.m41
                let v = transform.m12 * uv[0] + transform.m22 * uv[1] + transform.m42
                let rgb = try pixel(image, u: u, v: v)
                XCTAssertGreaterThan(rgb[0] + rgb[1] + rgb[2], 0.5,
                                     "\(identity.rawValue)'s actual face and cloth UVs must sample authored texels, rather than the atlas's empty black region.")
                if landmark == 0 {
                    XCTAssertGreaterThan(rgb[0], rgb[1])
                    XCTAssertGreaterThan(rgb[1], rgb[2], "The supplied cheek should sample warm skin rather than gray/green fabric.")
                }
            }
        }
    }

    func testActualSkinnedDriverKeepsHandsOnControlsDuringTransferAndReturns() throws {
        let jeep = WorldBuilder.makeJeep()
        let driver = try XCTUnwrap(jeep.childNode(withName: "playerDriver", recursively: true))
        XCTAssertNotNil(driver.childNode(withName: "gujarat_driver", recursively: true))
        let body = try XCTUnwrap(skinnedMeshes(in: driver).first { $0.name == "humanMesh" })
        let skin = try XCTUnwrap(body.skinner)
        let leftHand = try XCTUnwrap(skin.bones.first { $0.name == "hand.L" })
        let rightHand = try XCTUnwrap(skin.bones.first { $0.name == "hand.R" })
        var seatedPoints: [SIMD3<Float>] = []
        var seatedPosition = SCNVector3Zero
        for progress: Float in [0, 0.25, 0.5, 0.75, 1, 0] {
            WorldBuilder.poseDriver(in: jeep, progress: progress, time: 0)
            let points = try skinSamples(body)
            XCTAssertFalse(points.isEmpty)
            XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertTrue(points.allSatisfy { abs($0.x) < 1.4 && $0.y > 0.4 && $0.y < 3.1 && $0.z > -1.5 && $0.z < 1.6 },
                          "Bent limbs, face, clothes and hair must stay around the Jeep, with valid skin bind transforms.")
            if progress == 0 {
                if seatedPoints.isEmpty { seatedPoints = points; seatedPosition = driver.position }
                else {
                    XCTAssertEqual(points.count, seatedPoints.count)
                    let drift = zip(points, seatedPoints).map { simd_length($0 - $1) }.max() ?? 0
                    XCTAssertLessThan(drift, 0.003, "Returning to the seat restores the actual skinned vertex pose.")
                    XCTAssertEqual(driver.position.y, seatedPosition.y, accuracy: 0.001)
                }
                for hand in [leftHand, rightHand] {
                    let point = hand.convertPosition(SCNVector3Zero, to: jeep)
                    XCTAssertEqual(abs(point.x - 0.45), 0.22, accuracy: 0.06)
                    XCTAssertEqual(point.y, 1.48, accuracy: 0.06)
                    XCTAssertEqual(point.z, -0.47, accuracy: 0.06)
                }
            } else if progress == 1 {
                for hand in [leftHand, rightHand] {
                    let point = hand.convertPosition(SCNVector3Zero, to: jeep)
                    XCTAssertEqual(abs(point.x), 0.085, accuracy: 0.06)
                    XCTAssertEqual(point.y, 2.04, accuracy: 0.06)
                    XCTAssertEqual(point.z, 0.69, accuracy: 0.06)
                }
            }
        }
    }

    func testDeliveredExplorerAndGrandpaArticulateTheirLegsWhenWalking() throws {
        for identity: GujaratCharacter in [.explorer, .grandpa] {
            let person = WorldBuilder.makePedestrian(character: identity)
            XCTAssertNotNil(person.childNode(withName: "gujarat_\(identity.rawValue)", recursively: true))
            let body = try XCTUnwrap(skinnedMeshes(in: person).first { $0.name == "humanMesh" })
            let foot = try XCTUnwrap(body.skinner?.bones.first { $0.name == "foot.L" })
            WorldBuilder.poseWalker(person, phase: .pi / 2)
            let first = foot.simdWorldPosition
            let firstSkin = try skinSamples(body)
            WorldBuilder.poseWalker(person, phase: -.pi / 2)
            XCTAssertGreaterThan(simd_distance(foot.simdWorldPosition, first), 0.25)
            let secondSkin = try skinSamples(body)
            let displacement = zip(firstSkin, secondSkin).map { simd_length($0 - $1) }.max() ?? 0
            XCTAssertGreaterThan(displacement, 0.15, "Walking must deform the mesh, rather than move a rigid character.")
        }
    }

    private func skinnedMeshes(in root: SCNNode) -> [SCNNode] {
        var result: [SCNNode] = []
        root.enumerateChildNodes { node, _ in if node.skinner != nil { result.append(node) } }
        return result
    }

    private func finite(_ matrix: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { column in (0..<4).allSatisfy { matrix[column][$0].isFinite } }
    }

    private func values(_ source: SCNGeometrySource, at index: Int) -> [Float] {
        source.data.withUnsafeBytes { bytes in
            (0..<source.componentsPerVector).map { component in
                let offset = source.dataOffset + index * source.dataStride + component * source.bytesPerComponent
                if source.usesFloatComponents { return bytes.loadUnaligned(fromByteOffset: offset, as: Float.self) }
                if source.bytesPerComponent == 2 { return Float(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
                return Float(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
    }

    private func nearestVertex(in source: SCNGeometrySource, to target: SIMD3<Float>) -> Int {
        source.data.withUnsafeBytes { bytes in
            var nearest = 0
            var distance = Float.greatestFiniteMagnitude
            for index in 0..<source.vectorCount {
                let offset = source.dataOffset + index * source.dataStride
                let point = SIMD3(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
                                  bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                                  bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                let squared = simd_length_squared(point - target)
                if squared < distance { distance = squared; nearest = index }
            }
            return nearest
        }
    }

    private func pixel(_ image: CGImage, u: Float, v: Float) throws -> [Float] {
        let x = min(image.width - 1, max(0, Int(u * Float(image.width))))
        let y = min(image.height - 1, max(0, Int(v * Float(image.height))))
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                                  bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba.prefix(3).map { Float($0) / 255 }
    }

    /// CPU evaluation of the delivered vertex weights catches broken bind matrices hidden by root-only tests.
    private func skinSamples(_ actor: SCNNode) throws -> [SIMD3<Float>] {
        let skin = try XCTUnwrap(actor.skinner)
        let vertices = try XCTUnwrap(skin.baseGeometry?.sources(for: .vertex).first)
        let inverseBind = try XCTUnwrap(skin.boneInverseBindTransforms)
        let matrices = zip(skin.bones, inverseBind).map {
            $0.simdWorldTransform * simd_float4x4($1.scnMatrix4Value) * simd_float4x4(skin.baseGeometryBindTransform)
        }
        var result: [SIMD3<Float>] = []
        for index in stride(from: 0, to: vertices.vectorCount, by: max(1, vertices.vectorCount / 768)) {
            let p = values(vertices, at: index)
            let weights = values(skin.boneWeights, at: index)
            let joints = values(skin.boneIndices, at: index)
            XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.005)
            let vertex = SIMD4(p[0], p[1], p[2], 1)
            var point = SIMD4<Float>.zero
            for component in 0..<min(4, weights.count) where weights[component] > 0 {
                let joint = Int(joints[component])
                guard matrices.indices.contains(joint) else { XCTFail("Skin index exceeds the actual 22-bone rig."); continue }
                point += (matrices[joint] * vertex) * weights[component]
            }
            result.append(SIMD3(point.x, point.y, point.z))
        }
        return result
    }
}
