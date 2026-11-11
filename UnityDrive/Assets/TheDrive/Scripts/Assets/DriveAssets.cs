using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace TheDrive.UnityGame
{
    /// <summary>Loads the shipped, optimized Swift-game meshes without touching the source character pack.
    /// Mirror X changes handedness while preserving the game's -Z vehicle forward. All source colors are linear.
    /// Missing or invalid art is an explicit error, never a substituted primitive vehicle or avatar.</summary>
    public static class DriveAssets
    {
        [Serializable] public class Slice { public int offset, count; }
        [Serializable] public class Part { public string name; public int offset, count; public float[] position; }
        [Serializable] class Parts { public Part[] items; }
        [Serializable] class Body { public int count; }
        [Serializable] class EnvironmentModel { public string name; public Part[] parts; }
        [Serializable] class Environments { public EnvironmentModel[] items; }
        [Serializable] class Joint { public string name; public float[] translation, rotation, scale; public int[] children; }
        [Serializable] class Geometry { public string name; public Slice positions, normals, uv, joints, weights; public Slice[] triangles; public int[] materialIndices; }
        [Serializable] class Surface { public string name, baseColorTexture, normalTexture, metallicRoughnessTexture, alphaMode; public float[] baseColor; public float metallic, roughness; public bool doubleSided; }
        [Serializable] class Character { public int root; public Joint[] nodes; public int[] joints; public Slice inverseBind; public Geometry[] meshes; public Surface[] materials; }
        sealed class CharacterTemplate { public Character manifest; public Mesh[] meshes; public Material[] materials; }
        static readonly Dictionary<string, Mesh> meshes = new Dictionary<string, Mesh>();
        static readonly Dictionary<string, Material> materials = new Dictionary<string, Material>();
        static readonly Dictionary<string, CharacterTemplate> characters = new Dictionary<string, CharacterTemplate>();
        static readonly Dictionary<int, DriverRig> rigs = new Dictionary<int, DriverRig>();
        static readonly Dictionary<int, Transform[]> wheels = new Dictionary<int, Transform[]>();

        static TextAsset Asset(string path)
        {
            var asset = Resources.Load<TextAsset>("Drive/" + path);
            if (!asset) throw new InvalidOperationException("Required The Drive asset missing: Resources/Drive/" + path);
            return asset;
        }
        static string ManifestAsset(string path) { return Asset(path + "-manifest").text; }
        static byte[] Buffer(string path) { return Asset(path + "-buffer").bytes; }
        static float F(byte[] data, int at) { return BitConverter.ToSingle(data, at); }
        static Vector3 V(byte[] data, int at) { return new Vector3(-F(data, at), F(data, at + 4), F(data, at + 8)); }
        static Vector3 V(float[] a) { return new Vector3(-a[0], a[1], a[2]); }
        static Color C(float[] a) { return new Color(a[0], a[1], a[2], a[3]); }
        static Material Solid(string key, Color tint, float metallic = 0.1f, float smoothness = 0.4f, bool vertex = false)
        {
            Material value;
            if (materials.TryGetValue(key, out value)) return value;
            var shader = vertex ? Resources.Load<Shader>("Drive/VertexColorStandard") : Shader.Find("Standard");
            if (!shader) throw new InvalidOperationException("Required built-in Standard shader missing: " + key);
            value = new Material(shader) { name = key, color = tint };
            value.SetFloat("_Metallic", metallic); value.SetFloat("_Glossiness", smoothness);
            materials.Add(key, value); return value;
        }
        static void Transparent(Material mat)
        {
            mat.SetFloat("_Mode", 3); mat.SetInt("_SrcBlend", (int)BlendMode.SrcAlpha);
            mat.SetInt("_DstBlend", (int)BlendMode.OneMinusSrcAlpha); mat.SetInt("_ZWrite", 0);
            mat.EnableKeyword("_ALPHABLEND_ON"); mat.renderQueue = 3000;
        }
        static GameObject Render(string name, Mesh mesh, Material material, Transform parent)
        {
            var obj = new GameObject(name); obj.transform.SetParent(parent, false);
            obj.AddComponent<MeshFilter>().sharedMesh = mesh; obj.AddComponent<MeshRenderer>().sharedMaterial = material;
            return obj;
        }
        static Mesh Packed(string key, byte[] data, int offset, int count, int stride, byte[] colors = null)
        {
            Mesh mesh;
            if (meshes.TryGetValue(key, out mesh)) return mesh;
            if (count <= 0 || count % 3 != 0 || offset < 0 || offset + (long)count * stride > data.Length)
                throw new InvalidOperationException("Invalid mesh buffer: " + key);
            var vertices = new Vector3[count]; var normals = new Vector3[count]; var rgba = new Color[count];
            var uv = new Vector2[count]; var indices = new int[count];
            for (int i = 0; i < count; i++)
            {
                int at = offset + i * stride; vertices[i] = V(data, at); normals[i] = V(data, at + 12);
                if (stride == 40) rgba[i] = new Color(F(data, at + 24), F(data, at + 28), F(data, at + 32), F(data, at + 36));
                else { uv[i] = new Vector2(F(data, at + 24), F(data, at + 28));
                    int c = (offset / stride + i) * 16;
                    rgba[i] = colors == null ? Color.white : new Color(F(colors,c),F(colors,c+4),F(colors,c+8),F(colors,c+12)); }
                indices[i] = i % 3 == 0 ? i : i % 3 == 1 ? i + 1 : i - 1;
            }
            mesh = new Mesh { name = key, indexFormat = IndexFormat.UInt32, vertices = vertices, normals = normals, colors = rgba, uv = uv, triangles = indices };
            mesh.RecalculateBounds(); meshes.Add(key, mesh); return mesh;
        }
        public static GameObject CreateEnvironment(string name)
        {
            var models = JsonUtility.FromJson<Environments>("{\"items\":" + ManifestAsset("EnvironmentMesh") + "}").items;
            foreach (var model in models) if (model.name == name)
            {
                var root = new GameObject(name); var bytes = Buffer("EnvironmentMesh");
                foreach (var part in model.parts)
                    Render(name + "/" + part.name, Packed("environment/" + name + "/" + part.name, bytes, part.offset, part.count, 40),
                        Solid("environment " + part.name, Color.white, part.name == "window" ? 0.35f : 0.03f, part.name == "window" ? 0.8f : 0.15f, true), root.transform);
                return root;
            }
            throw new ArgumentException("Unknown imported environment model: " + name);
        }
        public static GameObject CreateJeep()
        {
            var jeep = new GameObject("Jeep");
            int count = JsonUtility.FromJson<Body>(ManifestAsset("JeepBody")).count;
            Render("sculptedBody", Packed("JeepBody", Buffer("JeepBody"), 0, count, 40), Solid("Jeep military paint", Color.white, 0.5f, 0.6f, true), jeep.transform);
            var parts = JsonUtility.FromJson<Parts>("{\"items\":" + ManifestAsset("Vehicle-suv") + "}").items;
            var wheelData = Buffer("Vehicle-suv"); var wheelColors = Buffer("Vehicle-suv-colors");
            var pivots = new List<Transform>();
            foreach (var part in parts) if (part.name.StartsWith("wheel-"))
            {
                var pivot = new GameObject(part.name); pivot.transform.SetParent(jeep.transform, false);
                // The sculpted Jeep uses wider axles and larger tires than the donor SUV.
                pivot.transform.localPosition = new Vector3(-Mathf.Sign(part.position[0]), 0.45f, part.name.Contains("front") ? -1 : 1);
                var wheel = Render("wheelMesh", Packed("suv/" + part.name,wheelData,part.offset,part.count,32,wheelColors), Solid("Wheel rubber and alloy",Color.white,0.15f,0.2f,true),pivot.transform);
                wheel.transform.localScale = Vector3.one * 1.2f; pivots.Add(pivot.transform);
            }
            wheels[jeep.GetInstanceID()] = pivots.ToArray();
            var driver = CreateCharacter("driver", true); driver.name = "playerDriver";
            driver.transform.SetParent(jeep.transform, false); driver.transform.localPosition = new Vector3(0.42f, 1.08f, -0.08f);
            var glass = new Material(Solid("Windshield source",new Color(0.55f,0.68f,0.7f,0.15f),0.05f,0.9f)); Transparent(glass);
            Primitive("foldedWindshield",PrimitiveType.Cube,jeep.transform,new Vector3(0,1.48f,-0.42f),new Vector3(1.5f,0.32f,0.04f),glass).transform.localRotation=Quaternion.Euler(-37,0,0);
            var dark = Solid("Turret steel", new Color(0.075f,0.085f,0.08f),0.8f,0.4f);
            var turret = new GameObject("turret"); turret.transform.SetParent(jeep.transform,false); turret.transform.localPosition=new Vector3(0,1.1f,0.85f);
            Primitive("mount",PrimitiveType.Cylinder,turret.transform,new Vector3(0,0.35f,0),new Vector3(.18f,.35f,.18f),dark);
            Primitive("receiver",PrimitiveType.Cube,turret.transform,new Vector3(0,1.02f,0.12f),new Vector3(.16f,.14f,.62f),dark);
            var barrel=Primitive("barrel",PrimitiveType.Cylinder,turret.transform,new Vector3(0,1.05f,-0.65f),new Vector3(.056f,.575f,.056f),dark);
            barrel.transform.localRotation=Quaternion.Euler(90,0,0);
            for(int side=-1;side<=1;side+=2) {
                Primitive("headlamp",PrimitiveType.Cylinder,jeep.transform,new Vector3(side*.65f,.95f,-1.7f),new Vector3(.24f,.035f,.24f),Solid("Headlamp",new Color(1,.86f,.56f),0,.6f)).transform.localRotation=Quaternion.Euler(90,0,0);
                Primitive("tailLight",PrimitiveType.Cube,jeep.transform,new Vector3(side*.65f,.85f,1.83f),new Vector3(.18f,.16f,.04f),Solid("Tail light",new Color(.7f,.025f,.01f),0,.5f));
            }
            return jeep;
        }
        static GameObject Primitive(string name, PrimitiveType type,Transform parent,Vector3 position,Vector3 scale,Material material)
        {
            var obj=GameObject.CreatePrimitive(type); obj.name=name; obj.transform.SetParent(parent,false);
            obj.transform.localPosition=position; obj.transform.localScale=scale; obj.GetComponent<Renderer>().sharedMaterial=material;
            var collider = obj.GetComponent<Collider>();
            if (Application.isPlaying) UnityEngine.Object.Destroy(collider); else UnityEngine.Object.DestroyImmediate(collider);
            return obj;
        }
        public static void AnimateJeep(GameObject jeep,float distance,float steering)
        {
            Transform[] list;
            if(!wheels.TryGetValue(jeep.GetInstanceID(),out list))return;
            foreach(var pivot in list) {
                pivot.localRotation=Quaternion.Euler(0,pivot.name.Contains("front") ? steering*26 : 0,0);
                pivot.GetChild(0).localRotation=Quaternion.Euler(distance/.432f*Mathf.Rad2Deg,0,0);
            }
        }
        static CharacterTemplate CharacterAsset(string kind)
        {
            CharacterTemplate cached;
            if(characters.TryGetValue(kind,out cached)) return cached;
            var manifest=JsonUtility.FromJson<Character>(ManifestAsset("Gujarat/"+kind));
            var bytes=Buffer("Gujarat/"+kind);
            if(manifest.joints.Length!=22 || manifest.inverseBind.count!=22)
                throw new InvalidOperationException("Expected the delivered 22-bone Gujarat rig: "+kind);
            var binds=new Matrix4x4[manifest.joints.Length];
            for(int i=0;i<binds.Length;i++) {
                var m=new Matrix4x4();
                for(int col=0;col<4;col++)for(int row=0;row<4;row++)
                    m[row,col]=F(bytes,manifest.inverseBind.offset+i*64+(col*4+row)*4)*(row==0?-1:1)*(col==0?-1:1);
                binds[i]=m;
            }
            cached=new CharacterTemplate {manifest=manifest,meshes=new Mesh[manifest.meshes.Length],materials=new Material[manifest.materials.Length]};
            for(int j=0;j<manifest.materials.Length;j++) {
                var surface=manifest.materials[j];
                var mat=new Material(Shader.Find("Standard")) {name=surface.name,color=C(surface.baseColor)};
                mat.SetFloat("_Metallic",surface.metallic); mat.SetFloat("_Glossiness",1-surface.roughness);
                if(!string.IsNullOrEmpty(surface.baseColorTexture))
                    mat.mainTexture=Texture(kind,surface.baseColorTexture);
                if(!string.IsNullOrEmpty(surface.normalTexture)) {
                    mat.SetTexture("_BumpMap",Texture(kind,surface.normalTexture)); mat.EnableKeyword("_NORMALMAP");
                }
                if(!string.IsNullOrEmpty(surface.metallicRoughnessTexture)) {
                    mat.SetTexture("_MetallicGlossMap",Resources.Load<Texture2D>("Drive/Gujarat/"+kind+"-standard-metallic"));
                    mat.SetFloat("_GlossMapScale",1); mat.EnableKeyword("_METALLICGLOSSMAP");
                }
                // The delivered normals/UVs are already bottom-origin: Unity requires no SceneKit V flip.
                if(surface.alphaMode=="BLEND") Transparent(mat);
                cached.materials[j]=mat;
            }
            for(int j=0;j<manifest.meshes.Length;j++) {
                var source=manifest.meshes[j]; int count=source.positions.count;
                var verts=new Vector3[count]; var norms=new Vector3[count]; var uv=new Vector2[count]; var weights=new BoneWeight[count];
                for(int i=0;i<count;i++) {
                    verts[i]=V(bytes,source.positions.offset+i*12); norms[i]=V(bytes,source.normals.offset+i*12);
                    uv[i]=new Vector2(F(bytes,source.uv.offset+i*8),F(bytes,source.uv.offset+i*8+4));
                    int at=source.joints.offset+i*8, wt=source.weights.offset+i*16;
                    weights[i]=new BoneWeight {boneIndex0=BitConverter.ToUInt16(bytes,at),boneIndex1=BitConverter.ToUInt16(bytes,at+2),boneIndex2=BitConverter.ToUInt16(bytes,at+4),boneIndex3=BitConverter.ToUInt16(bytes,at+6),weight0=F(bytes,wt),weight1=F(bytes,wt+4),weight2=F(bytes,wt+8),weight3=F(bytes,wt+12)};
                }
                var mesh=new Mesh {name=kind+"/"+source.name,indexFormat=IndexFormat.UInt32,vertices=verts,normals=norms,uv=uv,boneWeights=weights,bindposes=binds};
                mesh.subMeshCount=source.triangles.Length;
                for(int sub=0;sub<source.triangles.Length;sub++) {
                    var slice=source.triangles[sub]; var indices=new int[slice.count];
                    for(int i=0;i<indices.Length;i+=3) {
                        indices[i]=BitConverter.ToInt32(bytes,slice.offset+i*4);
                        indices[i+1]=BitConverter.ToInt32(bytes,slice.offset+(i+2)*4);
                        indices[i+2]=BitConverter.ToInt32(bytes,slice.offset+(i+1)*4);
                    }
                    mesh.SetTriangles(indices,sub);
                }
                mesh.RecalculateBounds(); mesh.RecalculateTangents(); cached.meshes[j]=mesh;
            }
            characters[kind]=cached; return cached;
        }
        static Texture2D Texture(string kind,string file)
        {
            string path="Drive/Gujarat/"+file.Substring(0,file.LastIndexOf('.'));
            var texture=Resources.Load<Texture2D>(path);
            if(!texture)throw new InvalidOperationException("Missing character texture: "+path);
            return texture;
        }
        public static GameObject CreateCharacter(string kind="driver",bool seated=true)
        {
            var asset=CharacterAsset(kind); var source=asset.manifest;
            var character=new GameObject("Gujarat "+kind); var nodes=new Transform[source.nodes.Length];
            for(int i=0;i<nodes.Length;i++) {
                var joint=source.nodes[i]; var node=new GameObject(joint.name).transform; nodes[i]=node;
                node.localPosition=V(joint.translation);
                node.localRotation=new Quaternion(joint.rotation[0],-joint.rotation[1],-joint.rotation[2],joint.rotation[3]);
                node.localScale=new Vector3(joint.scale[0],joint.scale[1],joint.scale[2]);
            }
            for(int i=0;i<nodes.Length;i++)foreach(int child in source.nodes[i].children)nodes[child].SetParent(nodes[i],false);
            var skeleton=nodes[source.root]; skeleton.SetParent(character.transform,false);
            var bones=new Transform[source.joints.Length]; for(int i=0;i<bones.Length;i++)bones[i]=nodes[source.joints[i]];
            for(int i=0;i<source.meshes.Length;i++) {
                var actor=new GameObject(source.meshes[i].name); actor.transform.SetParent(skeleton,false);
                var renderer=actor.AddComponent<SkinnedMeshRenderer>(); renderer.sharedMesh=asset.meshes[i]; renderer.bones=bones; renderer.rootBone=skeleton;
                var mats=new Material[source.meshes[i].materialIndices.Length];
                for(int j=0;j<mats.Length;j++)mats[j]=asset.materials[source.meshes[i].materialIndices[j]];
                renderer.sharedMaterials=mats; renderer.quality=SkinQuality.Bone4;
                renderer.localBounds=new Bounds(new Vector3(0,1,0),new Vector3(2.2f,3,2.4f));
            }
            var rig=new DriverRig(character.transform,skeleton,nodes,seated); rigs[character.GetInstanceID()]=rig;
            if(seated)rig.Pose(1,0,0);else rig.Standing(0);
            return character;
        }
        /// <summary>Scrub the seated-to-turret transfer. Progress 0 is driving; 1 is standing at the gun.</summary>
        public static void PoseDriver(GameObject root,float seatProgress,float time)
        {
            DriverRig rig; GameObject avatar=root;
            if(!rigs.TryGetValue(root.GetInstanceID(),out rig)) {
                var child=root.transform.Find("playerDriver"); if(!child)return;
                avatar=child.gameObject; if(!rigs.TryGetValue(avatar.GetInstanceID(),out rig))return;
            }
            float p=Mathf.Clamp01(seatProgress),ease=p*p*(3-2*p),step=Mathf.Sin(p*Mathf.PI);
            if(avatar!=root) {
                avatar.transform.localPosition=new Vector3(.42f*(1-ease),1.08f+.87f*ease+.12f*step,-.08f+.4f*ease);
                avatar.transform.localRotation=Quaternion.Euler(0,ease*180,0);
            }
            rig.Pose(1-ease,step,Mathf.Sin(time*2.2f)*.006f);
        }
        public static void PoseWalker(GameObject character,float phase)
        {
            DriverRig rig; if(rigs.TryGetValue(character.GetInstanceID(),out rig))rig.Standing(phase);
        }
        sealed class DriverRig
        {
            readonly Transform character,skeleton;
            readonly Dictionary<string,Transform> bones=new Dictionary<string,Transform>();
            readonly Dictionary<string,Vector3> positions=new Dictionary<string,Vector3>();
            readonly Dictionary<string,Quaternion> rotations=new Dictionary<string,Quaternion>();
            public DriverRig(Transform character,Transform skeleton,Transform[] nodes,bool seated)
            {
                this.character=character; this.skeleton=skeleton;
                foreach(var node in nodes) { bones[node.name]=node; positions[node.name]=skeleton.InverseTransformPoint(node.position); rotations[node.name]=Quaternion.Inverse(skeleton.rotation)*node.rotation; }
                skeleton.localRotation=Quaternion.Euler(0,180,0);
                if(seated)skeleton.localPosition=new Vector3(0,-1.18f,0);
            }
            Vector3 Point(float x,float y,float z) {return skeleton.InverseTransformPoint(character.TransformPoint(new Vector3(x,y,z)));}
            void Orient(string name,Quaternion rotation)
            {var bone=bones[name]; bone.rotation=skeleton.rotation*rotation;}
            void Solve(string upper,string lower,string tip,Vector3 target,Vector3 bend)
            {
                Vector3 pa=positions[upper],pb=positions[lower],pc=positions[tip];
                Vector3 origin=skeleton.InverseTransformPoint(bones[upper].position),delta=target-origin;
                float a=(pb-pa).magnitude,b=(pc-pb).magnitude;
                float distance=Mathf.Clamp(delta.magnitude,.04f,a+b-.005f);
                if(delta.sqrMagnitude<.000001f)return;
                Vector3 direction=delta.normalized;
                float along=(a*a-b*b+distance*distance)/(2*distance);
                float height=Mathf.Sqrt(Mathf.Max(0,a*a-along*along));
                Vector3 bendAxis=bend-direction*Vector3.Dot(bend,direction);
                if(bendAxis.sqrMagnitude<.001f)bendAxis=Vector3.right;
                Vector3 elbow=origin+direction*along+bendAxis.normalized*height;
                Orient(upper,Quaternion.FromToRotation(pb-pa,elbow-origin)*rotations[upper]);
                Vector3 lowerOrigin=skeleton.InverseTransformPoint(bones[lower].position);
                Orient(lower,Quaternion.FromToRotation(pc-pb,target-lowerOrigin)*rotations[lower]);
            }
            public void Pose(float seated,float step,float breath)
            {
                for(int side=-1;side<=1;side+=2) {
                    // Mirrored source L is +X after the seated yaw.
                    string suffix=side>0?".L":".R";
                    Vector3 foot=Point(side*.12f,-1.05f+seated*.39f+(side<0?step*.22f:0),-.05f-seated*.39f);
                    Solve("thigh"+suffix,"shin"+suffix,"foot"+suffix,foot,new Vector3(0,0,1));
                    Orient("foot"+suffix,rotations["foot"+suffix]);
                    var grip=Point(side*(.085f+seated*.135f),-.02f+(1-seated)*.11f+breath,-.39f-seated*.06f);
                    Solve("upper_arm"+suffix,"forearm"+suffix,"hand"+suffix,grip,new Vector3(side,-1,0));
                }
            }
            public void Standing(float phase)
            {
                float swing=Mathf.Sin(phase);
                for(int side=-1;side<=1;side+=2) {
                    string suffix=side>0?".L":".R"; float step=side*swing;
                    var foot=Point(side*.12f,.13f+Mathf.Max(0,step)*.16f,-.04f-step*.34f);
                    Solve("thigh"+suffix,"shin"+suffix,"foot"+suffix,foot,new Vector3(0,0,-1));
                    Orient("foot"+suffix,rotations["foot"+suffix]);
                    var hand=Point(side*.24f,.72f-Mathf.Abs(step)*.08f,step*.28f);
                    Solve("upper_arm"+suffix,"forearm"+suffix,"hand"+suffix,hand,new Vector3(0,0,1));
                }
            }
        }
    }
}
