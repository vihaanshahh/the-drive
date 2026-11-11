using System;
using System.Collections.Generic;
using UnityEngine;

namespace TheDrive.UnityGame
{
    /// <summary>Eight reusable road blocks. Absolute doubles drive the surface; transforms stay near the Jeep.</summary>
    public sealed class EndlessRoad : MonoBehaviour
    {
        public const float ChunkLength = 48f;
        public const int ChunkCount = 8;
        public const float AsphaltHalfWidth = 4.7f;
        private readonly List<Material> materials = new List<Material>();
        private readonly List<Mesh> meshes = new List<Mesh>();
        private readonly Chunk[] chunks = new Chunk[ChunkCount];
        private Material asphalt, sand, paint, dark, roof, wood;
        private Material[] plaster, cloth;
        private ulong seed;
        private bool initialized;

        private sealed class Chunk
        {
            public Transform Root;
            public long Index = long.MinValue;
            public Mesh Road, Ground, Lines;
            public readonly List<Shop> Shops = new List<Shop>();
            public readonly List<Transform> Houses = new List<Transform>();
        }
        private sealed class Shop
        {
            public Transform Root;
            public Renderer Walls, Awning, Sign;
            public Transform Body, Cap;
        }

        public void Initialize(ulong routeSeed)
        {
            if (initialized) { Reset(routeSeed); return; }
            seed = routeSeed;
            asphalt = Mat("Faded charcoal asphalt", new Color(.25f, .255f, .245f));
            sand = Mat("Warm desert sand", new Color(.76f, .61f, .40f));
            paint = Mat("Sun faded road paint", new Color(.89f, .69f, .28f));
            dark = Mat("Deep window recesses", new Color(.12f, .17f, .17f));
            roof = Mat("Pale roof coping", new Color(.83f, .72f, .53f));
            wood = Mat("Market timber", new Color(.29f, .22f, .15f));
            plaster = new[] { Mat("Ochre plaster", new Color(.71f,.45f,.25f)), Mat("Sandstone plaster", new Color(.80f,.64f,.43f)), Mat("Terracotta plaster", new Color(.65f,.34f,.23f)), Mat("Cream plaster", new Color(.85f,.75f,.56f)) };
            cloth = new[] { Mat("Turquoise canvas", new Color(.13f,.46f,.44f)), Mat("Rust canvas", new Color(.73f,.25f,.17f)), Mat("Saffron canvas", new Color(.88f,.59f,.16f)), Mat("Blue canvas", new Color(.23f,.35f,.49f)) };
            for (int i = 0; i < ChunkCount; i++) chunks[i] = CreateChunk(i);
            initialized = true;
            Reset(routeSeed);
        }

        public void Reset(ulong routeSeed)
        {
            if (!initialized) { Initialize(routeSeed); return; }
            seed = routeSeed;
            foreach (Chunk chunk in chunks) chunk.Index = long.MinValue;
            Advance(0, 0);
        }

        public void Advance(float step, double totalDistance)
        {
            if (!initialized || double.IsNaN(totalDistance) || double.IsInfinity(totalDistance)) return;
            long first = (long)Math.Floor(totalDistance / ChunkLength) - 1;
            for (int i = 0; i < ChunkCount; i++)
            {
                long index = first + i;
                int slot = (int)((index % ChunkCount + ChunkCount) % ChunkCount);
                Chunk chunk = chunks[slot];
                if (chunk.Index != index) Populate(chunk, index);
                chunk.Root.localPosition = new Vector3(0, 0, (float)(totalDistance - index * (double)ChunkLength));
            }
        }

        private Chunk CreateChunk(int number)
        {
            var chunk = new Chunk { Root = new GameObject("Road block " + number).transform };
            chunk.Root.SetParent(transform, false);
            chunk.Road = Surface(chunk.Root, "Rolling asphalt", asphalt);
            chunk.Ground = Surface(chunk.Root, "Sand and shoulders", sand);
            chunk.Lines = Surface(chunk.Root, "Worn lane markings", paint);
            for (int side = -1; side <= 1; side += 2)
                for (int j = 0; j < 3; j++) chunk.Shops.Add(CreateShop(chunk.Root, side));
            string[] houses = { "house_type02", "house_type06", "house_type01", "house_type08" };
            for (int i = 0; i < 4; i++)
            {
                Transform house = DriveAssets.CreateEnvironment(houses[(number + i) % houses.Length]).transform;
                house.SetParent(chunk.Root, false);
                chunk.Houses.Add(house);
            }
            return chunk;
        }

        private void Populate(Chunk chunk, long index)
        {
            chunk.Index = index;
            double start = index * (double)ChunkLength;
            var verts = new List<Vector3>(); var normals = new List<Vector3>(); var triangles = new List<int>();
            AddStrip(verts, normals, triangles, start, -AsphaltHalfWidth, AsphaltHalfWidth, 16, 64, .0f);
            Apply(chunk.Road, verts, normals, triangles);
            verts.Clear(); normals.Clear(); triangles.Clear();
            AddStrip(verts, normals, triangles, start, -100, -AsphaltHalfWidth, 8, 32, -.025f);
            AddStrip(verts, normals, triangles, start, AsphaltHalfWidth, 100, 8, 32, -.025f);
            Apply(chunk.Ground, verts, normals, triangles);
            verts.Clear(); normals.Clear(); triangles.Clear();
            // A 48 m block is six full 8 m paint cycles, so the pattern cannot jump at seams.
            for (int stripe = 0; stripe < 6; stripe++)
                AddRibbon(verts, normals, triangles, start, -.075f, .075f, stripe * 8 + 1, stripe * 8 + 4.2f);
            AddRibbon(verts, normals, triangles, start, -4.40f, -4.32f, 0, ChunkLength);
            AddRibbon(verts, normals, triangles, start, 4.32f, 4.40f, 0, ChunkLength);
            Apply(chunk.Lines, verts, normals, triangles);
            var random = new SeededRandom(unchecked(seed ^ (ulong)index * 0x9E3779B97F4A7C15UL ^ 0x5CE9EUL));
            for (int i = 0; i < chunk.Shops.Count; i++)
            {
                Shop shop = chunk.Shops[i];
                int side = i < 3 ? -1 : 1;
                float localDistance = 5 + (i % 3) * 15 + random.Range(-2f, 2f);
                float x = side * random.Range(10.5f, 14f);
                float y = RoadSurface.Height(start + localDistance, side * 5.7f, seed) - .05f;
                shop.Root.localPosition = new Vector3(x, y, -localDistance);
                shop.Root.localRotation = Quaternion.Euler(0, side < 0 ? 90 : -90, 0);
                // Slow changes in density make room for stretches of open desert after the bazaar.
                bool village = index < 4 || Math.Sin(index * .61) > -.25;
                shop.Root.gameObject.SetActive(village || i % 3 == 0);
                float height = random.Range(2.9f, 5.2f);
                shop.Body.localScale = new Vector3(7, height, 5.2f);
                shop.Body.localPosition = new Vector3(0, height / 2, 0);
                shop.Cap.localPosition = new Vector3(0, height + .12f, 0);
                shop.Walls.sharedMaterial = plaster[random.Range(0, plaster.Length)];
                shop.Awning.sharedMaterial = cloth[random.Range(0, cloth.Length)];
                shop.Sign.sharedMaterial = cloth[random.Range(0, cloth.Length)];
            }
            for (int i = 0; i < chunk.Houses.Count; i++)
            {
                int side = i < 2 ? -1 : 1;
                float d = 11 + (i % 2) * 25 + random.Range(-3f, 3f);
                Transform house = chunk.Houses[i];
                float x = side * random.Range(20f, 27f);
                house.localPosition = new Vector3(x, RoadSurface.Height(start + d, side * 5.7f, seed) - .07f, -d);
                house.localRotation = Quaternion.Euler(0, side < 0 ? -90 : 90, 0);
                house.gameObject.SetActive(index < 4 || Math.Sin(index * .61) > -.25 || i == 0);
            }
        }

        private void AddStrip(List<Vector3> vertices, List<Vector3> normals, List<int> triangles, double start, float left, float right, int columns, int rows, float lift)
        {
            int offset = vertices.Count;
            for (int row = 0; row <= rows; row++)
                for (int col = 0; col <= columns; col++)
                {
                    float x = Mathf.Lerp(left, right, col / (float)columns);
                    float d = row * ChunkLength / rows;
                    AddVertex(vertices, normals, start, x, d, lift);
                }
            for (int row = 0; row < rows; row++)
                for (int col = 0; col < columns; col++)
                {
                    int a = offset + row * (columns + 1) + col, b = a + 1, c = a + columns + 1;
                    triangles.Add(a); triangles.Add(b); triangles.Add(c);
                    triangles.Add(b); triangles.Add(c + 1); triangles.Add(c);
                }
        }

        private void AddRibbon(List<Vector3> vertices, List<Vector3> normals, List<int> triangles, double start, float left, float right, float from, float to)
        {
            int count = Mathf.Max(1, Mathf.CeilToInt((to - from) / .5f));
            int offset = vertices.Count;
            for (int j = 0; j <= count; j++)
            {
                float d = Mathf.Lerp(from, to, j / (float)count);
                AddVertex(vertices, normals, start, left, d, .014f);
                AddVertex(vertices, normals, start, right, d, .014f);
            }
            for (int j = 0; j < count; j++)
            {
                int a = offset + j * 2;
                triangles.Add(a); triangles.Add(a + 1); triangles.Add(a + 2);
                triangles.Add(a + 1); triangles.Add(a + 3); triangles.Add(a + 2);
            }
        }

        private void AddVertex(List<Vector3> vertices, List<Vector3> normals, double start, float x, float distance, float lift)
        {
            double d = start + distance;
            float h = RoadSurface.Height(d, x, seed);
            vertices.Add(new Vector3(x, h + lift, -distance));
            const float epsilon = .08f;
            float dx = (RoadSurface.Height(d, x + epsilon, seed) - RoadSurface.Height(d, x - epsilon, seed)) / (epsilon * 2);
            float dd = (RoadSurface.Height(d + epsilon, x, seed) - RoadSurface.Height(d - epsilon, x, seed)) / (epsilon * 2);
            normals.Add(new Vector3(-dx, 1, dd).normalized);
        }

        private static void Apply(Mesh mesh, List<Vector3> vertices, List<Vector3> normals, List<int> triangles)
        {
            mesh.Clear(); mesh.SetVertices(vertices); mesh.SetNormals(normals); mesh.SetTriangles(triangles, 0); mesh.RecalculateBounds();
        }

        private Shop CreateShop(Transform parent, int side)
        {
            var shop = new Shop { Root = new GameObject("Roadside bazaar shop").transform };
            shop.Root.SetParent(parent, false);
            shop.Body = Box(shop.Root, "Earthen shop", Vector3.zero, Vector3.one, plaster[0]);
            shop.Walls = shop.Body.GetComponent<Renderer>();
            shop.Cap = Box(shop.Root, "Flat roof coping", new Vector3(0,4,0), new Vector3(7.3f,.24f,5.5f), roof);
            Box(shop.Root, "Recessed doorway", new Vector3(-1.9f,1.15f,2.61f), new Vector3(1.3f,2.3f,.035f), dark);
            Box(shop.Root, "Shop window", new Vector3(1.4f,1.5f,2.62f), new Vector3(2.5f,1.4f,.045f), dark);
            Box(shop.Root, "Window sill", new Vector3(1.4f,.77f,2.73f), new Vector3(2.8f,.14f,.3f), roof);
            Transform canopy = Box(shop.Root, "Colored market awning", new Vector3(0,2.55f,3.5f), new Vector3(7.2f,.12f,2.2f), cloth[0]);
            canopy.localRotation = Quaternion.Euler(8,0,0);
            shop.Awning = canopy.GetComponent<Renderer>();
            shop.Sign = Box(shop.Root, "Painted shop fascia", new Vector3(0,2.34f,4.58f), new Vector3(7.2f,.4f,.08f), cloth[0]).GetComponent<Renderer>();
            for (int sign = -1; sign <= 1; sign += 2)
                Box(shop.Root, "Awning timber post", new Vector3(sign * 3.3f,1.2f,4.3f), new Vector3(.10f,2.4f,.1f), wood);
            Box(shop.Root, "Produce counter", new Vector3(1, .48f, 3.3f), new Vector3(2.8f,.9f,.9f), wood);
            for (int i = 0; i < 4; i++)
                Box(shop.Root, "Market goods", new Vector3(.0f + i * .65f,1.01f,3.3f), new Vector3(.52f,.22f,.60f), cloth[(i+2)%cloth.Length]);
            return shop;
        }

        private static Transform Box(Transform parent, string name, Vector3 position, Vector3 scale, Material material)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name; go.transform.SetParent(parent, false); go.transform.localPosition = position; go.transform.localScale = scale;
            go.GetComponent<Renderer>().sharedMaterial = material;
            if (Application.isPlaying) Destroy(go.GetComponent<Collider>());
            else DestroyImmediate(go.GetComponent<Collider>());
            return go.transform;
        }

        private Mesh Surface(Transform parent, string name, Material material)
        {
            var go = new GameObject(name); go.transform.SetParent(parent, false);
            var mesh = new Mesh { name = name }; mesh.MarkDynamic(); meshes.Add(mesh);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = material;
            return mesh;
        }

        private Material Mat(string name, Color color)
        {
            var material = new Material(Shader.Find("Standard")) { name = name, color = color };
            material.SetFloat("_Glossiness", .08f); materials.Add(material); return material;
        }

        private void OnDestroy()
        {
            foreach (Mesh mesh in meshes) if (mesh != null)
            {
                if (Application.isPlaying) Destroy(mesh); else DestroyImmediate(mesh);
            }
            foreach (Material material in materials) if (material != null)
            {
                if (Application.isPlaying) Destroy(material); else DestroyImmediate(material);
            }
        }
    }
}
