using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using Object = UnityEngine.Object;

namespace TheDrive.UnityGame.Tests
{
    public class AssetAndWorldTests
    {
        readonly List<GameObject> created = new List<GameObject>();
        GameObject Track(GameObject gameObject) { created.Add(gameObject); return gameObject; }

        [TearDown]
        public void Cleanup()
        {
            foreach (var gameObject in created) if (gameObject) Object.DestroyImmediate(gameObject);
            created.Clear();
        }

        static void Finite(Vector3 vector)
        {
            Assert.IsFalse(float.IsNaN(vector.x) || float.IsInfinity(vector.x));
            Assert.IsFalse(float.IsNaN(vector.y) || float.IsInfinity(vector.y));
            Assert.IsFalse(float.IsNaN(vector.z) || float.IsInfinity(vector.z));
        }
        static void ValidMesh(Mesh mesh)
        {
            Assert.IsNotNull(mesh);
            Assert.Greater(mesh.vertexCount, 0);
            foreach (var vertex in mesh.vertices) Finite(vertex);
            for (int sub = 0; sub < mesh.subMeshCount; sub++) {
                var indices = mesh.GetIndices(sub);
                Assert.Greater(indices.Length, 0);
                Assert.AreEqual(0, indices.Length % 3);
                foreach (var index in indices) Assert.That(index, Is.InRange(0, mesh.vertexCount - 1));
            }
            Finite(mesh.bounds.center); Finite(mesh.bounds.size);
        }

        [Test]
        public void ManifestAndBufferResourcesHaveDistinctKeys()
        {
            string[] keys = { "JeepBody", "EnvironmentMesh", "Vehicle-suv", "Vehicle-bike", "Vehicle-hatchback-sports", "Gujarat/driver", "Gujarat/explorer", "Gujarat/grandpa" };
            foreach (string key in keys) {
                var manifest = Resources.Load<TextAsset>("Drive/" + key + "-manifest");
                var buffer = Resources.Load<TextAsset>("Drive/" + key + "-buffer");
                Assert.IsNotNull(manifest, key + " manifest");
                Assert.IsNotNull(buffer, key + " buffer");
                Assert.AreNotEqual(manifest.GetInstanceID(), buffer.GetInstanceID());
                Assert.That(manifest.text.TrimStart()[0], Is.EqualTo('{').Or.EqualTo('['));
                Assert.Greater(buffer.bytes.Length, 10000);
            }
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string directory = Path.Combine(Application.dataPath, "TheDrive/Resources/Drive");
            foreach (string file in Directory.GetFiles(directory, "*", SearchOption.AllDirectories)) {
                string extension = Path.GetExtension(file).ToLowerInvariant();
                if (extension != ".json" && extension != ".bytes" && extension != ".txt") continue;
                string relative = file.Substring(directory.Length);
                string key = relative.Substring(0, relative.Length - extension.Length);
                Assert.IsTrue(seen.Add(key), "Ambiguous Unity TextAsset Resources key: " + key);
            }
        }

        [Test]
        public void JeepUsesSculptedSourceAndFourCenteredSteerableWheels()
        {
            var jeep = Track(DriveAssets.CreateJeep());
            var body = jeep.transform.Find("sculptedBody").GetComponent<MeshFilter>().sharedMesh;
            ValidMesh(body);
            Assert.AreEqual(7008, body.vertexCount, "The source sculpted shell must not become a primitive placeholder.");
            Assert.AreEqual(7008, body.triangles.Length);
            Assert.AreEqual(body.vertexCount, body.colors.Length);
            Assert.That(body.bounds.size.x, Is.EqualTo(2.56f).Within(.001f));
            Assert.That(body.bounds.size.z, Is.GreaterThan(3.7f));
            float brightest = 0;
            foreach (var color in body.colors) brightest = Mathf.Max(brightest, color.r, color.g, color.b);
            Assert.Greater(brightest, .2f);
            Assert.AreEqual("TheDrive/VertexColorStandard", jeep.transform.Find("sculptedBody").GetComponent<Renderer>().sharedMaterial.shader.name);
            Assert.IsNotNull(jeep.transform.Find("playerDriver"));
            Assert.AreEqual(22, jeep.GetComponentInChildren<SkinnedMeshRenderer>().bones.Length);
            int count = 0;
            DriveAssets.AnimateJeep(jeep, 7.5f, .5f);
            foreach (Transform child in jeep.transform) if (child.name.StartsWith("wheel-")) {
                count++;
                var wheel = child.GetChild(0);
                ValidMesh(wheel.GetComponent<MeshFilter>().sharedMesh);
                Assert.That(wheel.GetComponent<MeshFilter>().sharedMesh.bounds.center.sqrMagnitude, Is.LessThan(.0001f));
                Assert.That(child.localPosition.y, Is.EqualTo(.45f).Within(.001f));
                Assert.That(Mathf.Abs(child.localPosition.z), Is.EqualTo(1).Within(.001f));
                Assert.That(Mathf.Abs(child.localPosition.x), Is.EqualTo(1).Within(.001f));
                Assert.That(Mathf.Abs(Mathf.DeltaAngle(0, child.localEulerAngles.y)), Is.EqualTo(child.name.Contains("front") ? 13 : 0).Within(.001f));
                Assert.That(Quaternion.Angle(Quaternion.identity, wheel.localRotation), Is.GreaterThan(1));
            }
            Assert.AreEqual(4, count);
            foreach(float progress in new[] { 0f, .5f, 1f }) {
                DriveAssets.PoseDriver(jeep, progress, 10);
                AssertValidSkin(jeep);
            }
        }

        static void AssertValidSkin(GameObject character)
        {
            var renderers = character.GetComponentsInChildren<SkinnedMeshRenderer>();
            Assert.Greater(renderers.Length, 0);
            foreach (var renderer in renderers) {
                Assert.AreEqual(22, renderer.bones.Length);
                Assert.AreEqual(22, renderer.sharedMesh.bindposes.Length);
                ValidMesh(renderer.sharedMesh);
                var baked = new Mesh();
                try {
                    renderer.BakeMesh(baked);
                    Assert.AreEqual(renderer.sharedMesh.vertexCount, baked.vertexCount);
                    foreach(var vertex in baked.vertices) Finite(vertex);
                    baked.RecalculateBounds();
                    Finite(baked.bounds.center); Finite(baked.bounds.size);
                    Assert.That(baked.bounds.size.magnitude, Is.InRange(.001f, 5f));
                    Assert.That(baked.bounds.center.magnitude, Is.LessThan(5));
                } finally { Object.DestroyImmediate(baked); }
            }
        }

        [TestCase("driver", 39609)]
        [TestCase("explorer", 31269)]
        [TestCase("grandpa", 34253)]
        public void CastRetainsSourceRigAtlasAndFinitePosedSkin(string kind, int expectedTriangles)
        {
            var character = Track(DriveAssets.CreateCharacter(kind, false));
            int triangles = 0;
            foreach(var renderer in character.GetComponentsInChildren<SkinnedMeshRenderer>())
                triangles += renderer.sharedMesh.triangles.Length / 3;
            Assert.AreEqual(expectedTriangles, triangles);
            AssertValidSkin(character);
            DriveAssets.PoseWalker(character, 1.4f);
            AssertValidSkin(character);
            var human = character.GetComponentInChildren<SkinnedMeshRenderer>();
            var material = human.sharedMaterial;
            Assert.AreEqual("Standard", material.shader.name);
            Assert.IsNotNull(material.mainTexture);
            Assert.IsNotNull(material.GetTexture("_BumpMap"));
            Assert.IsNotNull(material.GetTexture("_MetallicGlossMap"));
            Assert.AreEqual(Vector2.one, material.mainTextureScale, "Unity atlases must retain bottom-origin UVs without SceneKit's V flip.");
            Assert.AreEqual(Vector2.zero, material.mainTextureOffset);
            // Read a separate PNG copy: imported mobile textures need not be CPU-readable.
            var atlas = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            try {
                string file = Path.Combine(Application.dataPath, "TheDrive/Resources/Drive/Gujarat/" + kind + "-color.png");
                Assert.IsTrue(atlas.LoadImage(File.ReadAllBytes(file)));
                var uv = human.sharedMesh.uv;
                Assert.AreEqual(human.sharedMesh.vertexCount, uv.Length);
                float brightest = 0;
                for(int i = 0; i < uv.Length; i += Math.Max(1, uv.Length / 2000)) {
                    Assert.IsFalse(float.IsNaN(uv[i].x) || float.IsNaN(uv[i].y));
                    var color = atlas.GetPixelBilinear(uv[i].x, uv[i].y);
                    brightest = Mathf.Max(brightest, color.r, color.g, color.b);
                }
                Assert.Greater(brightest, .25f, "Source wardrobe UVs must sample visible atlas content.");
            } finally { Object.DestroyImmediate(atlas); }
        }

        [Test]
        public void ImportedHouseHasSourceGeometryAndWorldRemainsBoundedAfterTenThousandFramesAndReset()
        {
            var house = Track(DriveAssets.CreateEnvironment("house_type01"));
            int vertices = 0;
            foreach(var filter in house.GetComponentsInChildren<MeshFilter>()) { ValidMesh(filter.sharedMesh); vertices += filter.sharedMesh.vertexCount; }
            Assert.Greater(vertices, 500, "Use the modeled source house, not a box placeholder.");
            var root = Track(new GameObject("World pool test"));
            var road = root.AddComponent<EndlessRoad>(); road.Initialize(123);
            Assert.AreEqual(EndlessRoad.ChunkCount, root.transform.childCount);
            int objects = root.GetComponentsInChildren<Transform>(true).Length;
            var meshIds = new HashSet<int>();
            foreach(var filter in root.GetComponentsInChildren<MeshFilter>(true))meshIds.Add(filter.sharedMesh.GetInstanceID());
            for(int frame = 1; frame <= 10000; frame++)road.Advance(1f/60, frame * 33.3 / 60);
            road.Reset(456);
            road.Initialize(789);
            Assert.AreEqual(8, root.transform.childCount);
            Assert.AreEqual(objects, root.GetComponentsInChildren<Transform>(true).Length);
            foreach(var filter in root.GetComponentsInChildren<MeshFilter>(true)) {
                Assert.IsTrue(meshIds.Contains(filter.sharedMesh.GetInstanceID()), "Road recycling must reuse existing meshes.");
                Finite(filter.transform.position);
            }
            foreach(Transform chunk in root.transform)Assert.That(Mathf.Abs(chunk.localPosition.z),Is.LessThanOrEqualTo(EndlessRoad.ChunkLength * 7));
        }
    }
}
