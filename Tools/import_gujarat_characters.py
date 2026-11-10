#!/usr/bin/env python3
"""Make the user-provided Gujarat character ZIP mobile-ready, without running its scripts.

    python3 Tools/import_gujarat_characters.py /path/Gujarat_Desert_Characters_Pack.zip

Only Python's standard library and Blender (including its NumPy) are required. Source
GLBs are treated as data. The imported FK pose is cleared; original skin influences
survive controlled per-component decimation and are normalized to four per vertex.
Opaque materials are baked into small PBR atlases without changing the authored UVs'
repeat behavior. Output UVs use Blender's bottom-origin convention; the paired SceneKit
loader flips material V when sampling top-origin UIImage maps. No runtime glTF reader
or original presentation meshes are bundled.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
import zipfile

KINDS = ('driver', 'explorer', 'grandpa')
BUDGETS = {'driver': 31_500, 'explorer': 21_000, 'grandpa': 21_000}


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or length != len(raw):
        raise ValueError('Invalid GLB: ' + str(path))
    size, kind = struct.unpack_from('<II', raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError('Missing GLB JSON')
    doc = json.loads(raw[20:20 + size])
    bsize, bkind = struct.unpack_from('<II', raw, 20 + size)
    if bkind != 0x004E4942:
        raise ValueError('Missing GLB binary')
    return doc, raw[28 + size:28 + size + bsize]


def png_read(raw):
    """Use Blender's native PNG decoder, reading raw encoded texels in Non-Color mode."""
    import bpy
    import numpy as np
    if raw[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Expected PNG source texture')
    with tempfile.NamedTemporaryFile(suffix='.png') as source:
        source.write(raw); source.flush()
        image = bpy.data.images.load(source.name, check_existing=False)
        image.colorspace_settings.name = 'Non-Color'
        w, h = image.size
        pixels = np.empty(w * h * 4, np.float32)
        image.pixels.foreach_get(pixels)
        result = pixels.reshape(h, w, 4)[::-1, :, :3].copy()
        bpy.data.images.remove(image)
        return result


def png_write(path, image):
    import numpy as np
    pixels = np.clip(np.round(image * 255), 0, 255).astype(np.uint8)
    h, w, c = pixels.shape
    if c not in (3, 4):
        raise ValueError('Atlas must be RGB or RGBA')
    def chunk(tag, payload):
        return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff)
    rows = b''.join(b'\0' + row.tobytes() for row in pixels)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2 if c == 3 else 6, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


def atlas_for(doc, binary, out, kind):
    import numpy as np
    mats = doc['materials']; cache = {}
    def image(texture):
        idx = doc['textures'][texture['index']]['source']
        if idx not in cache:
            view = doc['bufferViews'][doc['images'][idx]['bufferView']]
            cache[idx] = png_read(binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']])
        return cache[idx]
    def linear(x):
        return np.where(x <= .04045, x / 12.92, ((x + .055) / 1.055) ** 2.4)
    def srgb(x):
        x = np.maximum(x, 0)
        return np.where(x <= .0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - .055)
    def resize(x, size):
        # Atlas rects are powers of two and source maps are 2048 square. Average
        # the complete source texel footprint, retaining woven/embroidered detail.
        factor = x.shape[0] // size
        return x.reshape(size, factor, size, factor, 3).mean(axis=(1, 3))
    color = np.zeros((1024, 1024, 3), np.float32)
    normal = np.empty_like(color); normal[:] = [.5, .5, 1]
    mr = np.empty_like(color); mr[:] = [1, 1, 0]
    rects = {}; constants = []; occupied = {(0,0),(1,0),(0,1),(1,1),(3,3)}
    free = [(x, y) for y in range(4) for x in range(4) if (x, y) not in occupied]
    for m in mats:
        p = m.get('pbrMetallicRoughness', {})
        if m.get('alphaMode') == 'BLEND' or 'glass' in m['name'].lower():
            continue
        factor = np.array(p.get('baseColorFactor', [1,1,1,1])[:3], dtype=np.float32)
        if 'baseColorTexture' in p:
            if 'vest' in m['name'].lower():
                x, y, size = 0, 0, 512
            else:
                if not free:
                    raise ValueError('Too many textile materials for mobile atlas')
                gx, gy = free.pop(0); x, y, size = gx * 256, gy * 256, 256
            source = resize(linear(image(p['baseColorTexture'])), size - 0)
            base = srgb(source * factor)
            rough = float(p.get('roughnessFactor', 1)); metal = float(p.get('metallicFactor', 1))
            packed = resize(image(p['metallicRoughnessTexture']), size) if 'metallicRoughnessTexture' in p else np.ones_like(base)
            packed[:, :, 0] = 1; packed[:, :, 1] *= rough; packed[:, :, 2] *= metal
            n = resize(image(m['normalTexture']), size) if 'normalTexture' in m else np.tile([.5,.5,1], (size,size,1))
            vec = n * 2 - 1; vec[:, :, :2] *= m.get('normalTexture', {}).get('scale', 1)
            vec /= np.maximum(1e-8, np.linalg.norm(vec, axis=2, keepdims=True)); n = vec * .5 + .5
        else:
            # Flat shader factors are authored in linear light, never interpreted
            # as sRGB paint values. This preserves the supplied complexions.
            i = len(constants); constants.append(m['name']); size = 16
            x, y = 768 + (i % 16) * size, 768 + (i // 16) * size
            base = np.tile(srgb(factor), (size,size,1))
            packed = np.tile([1, float(p.get('roughnessFactor', 1)), float(p.get('metallicFactor', 1))], (size,size,1))
            n = np.tile([.5,.5,1], (size,size,1))
        # Two-pixel wrap gutters prevent neighboring fabrics bleeding into an atlas
        # cell. The image stays power-of-two; UVs address only its inner texels.
        gutter = 2
        for target, source in [(color,base),(normal,n),(mr,packed)]:
            interior = source[gutter:-gutter, gutter:-gutter]
            padded = np.pad(interior, ((gutter,gutter),(gutter,gutter),(0,0)), mode='wrap')
            target[y:y+size, x:x+size] = padded
        rects[m['name']] = (x + gutter + .5, y + gutter + .5, size - 2 * gutter - 1, size - 2 * gutter - 1)
    names = {}
    for label, pixels in [('color',color),('normal',normal),('metallic-roughness',mr)]:
        name = f'{kind}-{label}.png'; png_write(out / name, pixels); names[label] = name
    materials = [dict(name=f'{kind}_authored_PBR_atlas', baseColor=[1,1,1,1], metallic=1, roughness=1,
                      baseColorTexture=names['color'], normalTexture=names['normal'],
                      metallicRoughnessTexture=names['metallic-roughness'], doubleSided=True,
                      alphaMode='OPAQUE')]
    glass = dict(name=f'{kind}_source_goggle_glass', baseColor=[.1651322,.2622507,.2345506,1],
                 metallic=.15,roughness=.14,doubleSided=True,alphaMode='OPAQUE')
    cornea = dict(name=f'{kind}_source_cornea',baseColor=[1,1,1,.08],metallic=0,
                  roughness=.07,doubleSided=True,alphaMode='BLEND')
    materials.extend([glass, cornea])
    return rects, materials


def desired_triangles(obj):
    name = obj.name.lower(); n = len(obj.data.loop_triangles)
    if 'fine_hair_strands' in name: return 650
    if 'primary_hair_strands' in name: return 2800
    if 'hair_highlight' in name: return 450
    if 'anatomical_head_and_neck' in name: return 6500
    if 'forearm_and_hand' in name: return 1950
    if 'anatomical_hair_scalp' in name: return 1200
    if any(x in name for x in ('iris','pupil','cornea','sclera','eyeball')): return min(n,144)
    if 'eyebrow' in name: return 450
    if 'eyelash' in name: return 180
    if 'stubble' in name: return 200
    if 'sculpted_khadi_tunic' in name: return 2200
    if 'shaped_canvas_trouser' in name: return 1300
    if 'dhoti' in name: return min(n,1100)
    if 'padded_vest' in name: return 800
    if 'sculpted_rolled_sleeve' in name: return 550
    if 'draped_folded' in name: return 1100
    if 'sculpted_leather_boot' in name: return 600
    if 'goggle' in name: return min(n,140)
    if 'braid' in name or 'hair' in name: return min(n,1300)
    return max(8,min(220,n*.045))


def prune_hair_components(obj, target):
    """Retain an evenly distributed subset of expensive disconnected fine strands."""
    import bmesh
    n = obj.name.lower()
    if not any(x in n for x in ('fine_hair_strands','hair_highlight')):
        return 0
    bm=bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
    seen=set(); components=[]
    for vertex in bm.verts:
        if vertex.index in seen: continue
        stack=[vertex]; seen.add(vertex.index); component=[]
        while stack:
            current=stack.pop(); component.append(current)
            for edge in current.link_edges:
                other=edge.other_vert(current)
                if other.index not in seen: seen.add(other.index); stack.append(other)
        components.append(component)
    keep=min(len(components), max(16, int(target)//8))
    selected={int((i+.5)*len(components)/keep) for i in range(keep)}
    discard=[v for i,c in enumerate(components) if i not in selected for v in c]
    bmesh.ops.delete(bm, geom=discard, context='VERTS')
    bm.to_mesh(obj.data); bm.free(); obj.data.update()
    return len(components)-keep


def clip_poly(poly, axis, boundary, keep_greater):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        va=a['uv'][axis]-boundary; vb=b['uv'][axis]-boundary
        ia=va>=-1e-8 if keep_greater else va<=1e-8
        ib=vb>=-1e-8 if keep_greater else vb<=1e-8
        if ia: result.append(a)
        if ia != ib:
            t=va/(va-vb); v={}
            for name in ('p','n','uv'): v[name]=a[name]*(1-t)+b[name]*t
            combined={}
            for source,weight in [(a,1-t),(b,t)]:
                for joint,value in source['skin'].items(): combined[joint]=combined.get(joint,0)+value*weight
            v['skin']=combined;result.append(v)
    return result


def worker(source, out, only, budgets, preview):
    import bpy
    import numpy as np
    from mathutils import Matrix, Vector
    out.mkdir(parents=True, exist_ok=True)
    all_stats={}
    for kind in only:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        path=source/'exports'/f'{kind}.glb'
        doc,binary=read_glb(path)
        rects,materials=atlas_for(doc,binary,out,kind)
        bpy.ops.import_scene.gltf(filepath=str(path))
        rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
        rig.data.pose_position='REST'
        for bone in rig.pose.bones: bone.matrix_basis=Matrix.Identity(4)
        objects=sorted([o for o in bpy.data.objects if o.type=='MESH' and len(o.data.materials)>0],key=lambda o:o.name)
        before=0
        for obj in objects:
            for modifier in list(obj.modifiers): obj.modifiers.remove(modifier)
            obj.data.calc_loop_triangles(); before+=len(obj.data.loop_triangles)
        desired={o.name:desired_triangles(o) for o in objects}
        scale=min(1,budgets[kind]/sum(desired.values()))
        if kind!='driver':scale*=.77
        pruned=0
        for obj in objects:
            target=max(8,int(desired[obj.name]*scale))
            pruned+=prune_hair_components(obj,target)
            obj.data.calc_loop_triangles(); count=len(obj.data.loop_triangles)
            if count>target:
                bpy.context.view_layer.objects.active=obj;obj.select_set(True)
                modifier=obj.modifiers.new('Mobile silhouette-preserving reduction','DECIMATE')
                modifier.decimate_type='COLLAPSE';modifier.ratio=target/count;modifier.use_collapse_triangulate=True
                bpy.ops.object.modifier_apply(modifier=modifier.name)
                obj.select_set(False)
            obj.data.calc_loop_triangles()
        # A positive-determinant rotation changes Blender Z-up/-Y-forward into
        # SceneKit Y-up/+Z-forward. Position, normals, joints and binds use it together.
        C=Matrix.Rotation(-math.pi/2,4,'X'); invC=C.inverted()
        bones=list(rig.data.bones);bone_lookup={b.name:i for i,b in enumerate(bones)}
        nodes=[dict(name=f'gujarat_{kind}',translation=[0,0,0],rotation=[0,0,0,1],scale=[1,1,1],children=[1]),
               dict(name='GujaratSkeleton',translation=[0,0,0],rotation=[0,0,0,1],scale=[1,1,1],children=[])]
        global_bones=[C@b.matrix_local@invC for b in bones]
        for i,bone in enumerate(bones):
            matrix=global_bones[i]
            if bone.parent:matrix=global_bones[bone_lookup[bone.parent.name]].inverted()@matrix
            t,q,s=matrix.decompose()
            nodes.append(dict(name=bone.name,translation=list(t),rotation=[q.x,q.y,q.z,q.w],scale=list(s),children=[]))
        for i,bone in enumerate(bones):
            parent=bone_lookup[bone.parent.name]+2 if bone.parent else 1
            nodes[parent]['children'].append(i+2)
        groups={}
        bounds_min=np.array([math.inf]*3);bounds_max=-bounds_min
        unweighted=0;max_skin_error=0;goggles_moved=0
        for obj in objects:
            mesh=obj.data;mesh.calc_loop_triangles()
            if not mesh.polygons:continue
            if not mesh.materials:raise ValueError('Missing material after optimization: '+obj.name)
            goggle=kind=='driver' and 'goggle' in obj.name.lower()
            transparent=all(m and 'cornea' in m.name.lower() for m in mesh.materials)
            lens=goggle and any(m and 'glass' in m.name.lower() for m in mesh.materials)
            group=('sunglassLens_'+('left' if 'left' in obj.name.lower() or obj.name.endswith('.001') else 'right')) if lens else 'sunglasses' if goggle else 'cornea' if transparent else 'humanMesh'
            if group not in groups: groups[group]=dict(vertices=[],indices={},lookup={})
            group_data=groups[group]
            matrix=C@rig.matrix_world.inverted()@obj.matrix_world
            normals=matrix.to_3x3().inverted().transposed()
            group_names={g.index:g.name for g in obj.vertex_groups}
            skins={}
            for vertex in mesh.vertices:
                influence={bone_lookup[group_names[g.group]]:g.weight for g in vertex.groups if group_names[g.group] in bone_lookup and g.weight>1e-8}
                if goggle: influence={bone_lookup['head']:1.0}
                if not influence: influence={bone_lookup['spine']:1.0};unweighted+=1
                skins[vertex.index]=influence
            uv_layer=mesh.uv_layers.active
            corner_normals=mesh.corner_normals
            for triangle in mesh.loop_triangles:
                mat=mesh.materials[triangle.material_index]
                if not mat:continue
                name=mat.name
                material_index=1 if 'glass' in name.lower() else 2 if 'cornea' in name.lower() else 0
                rect=rects.get(name)
                poly=[]
                for vi,li in zip(triangle.vertices,triangle.loops):
                    p=matrix@mesh.vertices[vi].co;n=normals@corner_normals[li].vector;n.normalize()
                    if goggle:p+=Vector((0,.29,-.05));goggles_moved+=1
                    uv=np.array(uv_layer.data[li].uv if uv_layer else (.5,.5),np.float64)
                    poly.append(dict(p=np.array(p),n=np.array(n),uv=uv,skin=skins[vi]))
                face_normal=np.cross(poly[1]['p']-poly[0]['p'],poly[2]['p']-poly[0]['p'])
                face_length=np.linalg.norm(face_normal)
                if face_length<1e-12:continue
                face_normal/=face_length
                for v in poly:
                    if np.linalg.norm(v['n'])<1e-6:v['n']=face_normal.copy()
                # Split triangles only where tiled textile UVs cross integer seams;
                # interpolation preserves positions, smooth normals and original skin.
                pieces=[]
                if rect and 'baseColorTexture' in next(m for m in doc['materials'] if m['name']==name).get('pbrMetallicRoughness',{}):
                    low=np.floor(np.min([v['uv']for v in poly],axis=0)+1e-7).astype(int)
                    high=np.floor(np.max([v['uv']for v in poly],axis=0)-1e-7).astype(int)
                    high=np.maximum(low,high)
                    if np.any(high-low>16):raise ValueError('Unexpected textile UV span')
                    for tx in range(low[0],high[0]+1):
                        for ty in range(low[1],high[1]+1):
                            clipped=poly
                            for axis,edge,greater in [(0,tx,True),(0,tx+1,False),(1,ty,True),(1,ty+1,False)]:
                                if clipped:clipped=clip_poly(clipped,axis,edge,greater)
                            if len(clipped)>=3:pieces.append((clipped,(tx,ty)))
                else:pieces=[(poly,(0,0))]
                for clipped,tile in pieces:
                    ids=[]
                    for v in clipped:
                        if rect:
                            x,y,w,h=rect
                            if len(pieces)==1 and not ('baseColorTexture' in next(m for m in doc['materials'] if m['name']==name).get('pbrMetallicRoughness',{})):
                                uv=np.array([(x+w*.5)/1024,1-(y+h*.5)/1024])
                            else:
                                u,vert=v['uv']-tile
                                uv=np.array([(x+min(1,max(0,u))*w)/1024,1-(y+(1-min(1,max(0,vert)))*h)/1024])
                        else:uv=v['uv']
                        sk=sorted(v['skin'].items(),key=lambda x:(-x[1],x[0]))[:4];total=sum(x[1]for x in sk)
                        indices=[x[0]for x in sk]+[0]*(4-len(sk));weights=[x[1]/total for x in sk]+[0.]*(4-len(sk))
                        max_skin_error=max(max_skin_error,abs(sum(weights)-1))
                        nlength=np.linalg.norm(v['n'])
                        nn=v['n']/nlength if nlength>1e-6 else face_normal
                        key=tuple(round(float(x),7)for x in [*v['p'],*nn,*uv,*weights])+tuple(indices)
                        idx=group_data['lookup'].get(key)
                        if idx is None:
                            idx=len(group_data['vertices']);group_data['lookup'][key]=idx
                            group_data['vertices'].append((v['p'],nn,uv,indices,weights))
                            bounds_min=np.minimum(bounds_min,v['p']);bounds_max=np.maximum(bounds_max,v['p'])
                        ids.append(idx)
                    output=group_data['indices'].setdefault(material_index,[])
                    for j in range(1,len(ids)-1):
                        if len({ids[0],ids[j],ids[j+1]})==3:output.extend([ids[0],ids[j],ids[j+1]])
        data=bytearray()
        def pack(values,dtype,components=1):
            while len(data)%4:data.append(0)
            offset=len(data);a=np.asarray(values,dtype=dtype);data.extend(a.tobytes())
            return dict(offset=offset,count=int(a.size//components))
        inverse=pack([[float(m.inverted()[r][c])for c in range(4)for r in range(4)]for m in global_bones],'<f4',16)
        meshes=[];total_vertices=0;total_triangles=0
        for name,group in groups.items():
            vertices=group['vertices']
            if not vertices:continue
            elements=[];material_indices=[]
            for mat,indices in sorted(group['indices'].items()):
                if indices:elements.append(pack(indices,'<u4'));material_indices.append(mat);total_triangles+=len(indices)//3
            m=dict(name='sunglassLens' if name.startswith('sunglassLens') else name,
                   positions=pack([v[0]for v in vertices],'<f4',3),normals=pack([v[1]for v in vertices],'<f4',3),
                   uv=pack([v[2]for v in vertices],'<f4',2),joints=pack([v[3]for v in vertices],'<u2',4),
                   weights=pack([v[4]for v in vertices],'<f4',4),triangles=elements,materialIndices=material_indices,
                   group='sunglasses' if name.startswith('sunglass') else '')
            meshes.append(m);total_vertices+=len(vertices)
        stats=dict(sourceTriangles=before,triangles=total_triangles,vertices=total_vertices,joints=len(bones),
                   meshes=len(meshes),drawCalls=sum(len(m['triangles'])for m in meshes),
                   sourceMeshObjects=len(objects),removedFineHairComponents=pruned,
                   fallbackUnweightedVertices=unweighted,maxWeightSumError=max_skin_error,
                   bounds=dict(min=bounds_min.tolist(),max=bounds_max.tolist()),binaryBytes=len(data),goggleVerticesPromoted=goggles_moved)
        result=dict(version=1,kind=kind,root=0,skeleton=1,nodes=nodes,joints=list(range(2,len(bones)+2)),inverseBind=inverse,
                    meshes=meshes,materials=materials,coordinates='metres; Y up; +Z forward; positive-determinant rotation',
                    source=dict(file=path.name,sha256=digest(path)),stats=stats)
        validate(result,data)
        (out/f'{kind}.bin').write_bytes(data);(out/f'{kind}.json').write_text(json.dumps(result,indent=2)+'\n')
        all_stats[kind]=stats
        print('MOBILE_CHARACTER',kind,json.dumps(stats),flush=True)
        if preview:render_preview(bpy,objects,rig,out,kind)
    return all_stats


def validate(manifest,data):
    """Independent binary range, finite geometry, unit normals and normalized skin checks."""
    import numpy as np
    for mesh in manifest['meshes']:
        count=mesh['positions']['count']
        values={}
        for name,width,dtype in [('positions',3,'<f4'),('normals',3,'<f4'),('uv',2,'<f4'),('joints',4,'<u2'),('weights',4,'<f4')]:
            s=mesh[name];a=np.frombuffer(data,dtype=dtype,count=s['count']*width,offset=s['offset']).reshape(-1,width)
            assert len(a)==count and np.isfinite(a).all(),(name,'invalid vertex data')
            values[name]=a
        assert np.max(np.abs(np.linalg.norm(values['normals'],axis=1)-1))<1e-4
        assert np.max(np.abs(values['weights'].sum(axis=1)-1))<1e-5
        assert values['joints'].max()<len(manifest['joints']) and values['weights'].min()>=0
        for s in mesh['triangles']:
            a=np.frombuffer(data,dtype='<u4',count=s['count'],offset=s['offset'])
            assert len(a)%3==0 and a.max()<count
    assert manifest['stats']['fallbackUnweightedVertices']==0
    box=manifest['stats']['bounds']
    assert 1.5<box['max'][1]-box['min'][1]<2.2 and box['min'][1]>-.05


def render_preview(bpy,objects,rig,out,kind):
    # Optional source-space mesh check. Runtime SceneKit checks remain authoritative.
    from mathutils import Vector
    rig.hide_render=True
    bpy.ops.object.camera_add(location=(2.3,-4,1.6));camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,1))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=2.4;bpy.context.scene.camera=camera
    for location,power,size in [((2,-3,4),650,4),((-2,-2,3),450,3)]:
        bpy.ops.object.light_add(type='AREA',location=location);bpy.context.object.data.energy=power;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=size
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=12
    scene.render.resolution_x=600;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.world.color=(.12,.12,.12);scene.render.filepath=str(out/f'{kind}-conversion-preview.png')
    bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path,help='Character pack ZIP or extracted Gujarat_Desert_Characters directory')
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parents[1]/'TheDrive/Assets/Gujarat')
    parser.add_argument('--blender',default='/Applications/Blender.app/Contents/MacOS/Blender')
    parser.add_argument('--only',choices=KINDS,nargs='+',default=list(KINDS))
    parser.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
    parser.add_argument('--preview',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else None)
    if args.worker:
        worker(args.source.resolve(),args.out.resolve(),args.only,BUDGETS,args.preview)
        return
    task_tmp=None
    source=args.source.resolve()
    zip_sha=None
    if source.is_file():
        zip_sha=digest(source);task_tmp=tempfile.TemporaryDirectory(prefix='the-drive-gujarat-import-')
        extracted=Path(task_tmp.name)
        with zipfile.ZipFile(source) as archive:
            keep=[]
            for info in archive.infolist():
                p=Path(info.filename)
                if p.is_absolute() or '..' in p.parts:raise ValueError('Unsafe ZIP member')
                if p.name in ('README.txt','ASSET_CREDITS.txt','manifest.json','model_stats.json') or (p.parent.name=='exports' and p.name in [f'{k}.glb'for k in args.only]):
                    keep.append(info)
            archive.extractall(extracted,members=keep)
        source=next(p.parent for p in extracted.rglob('README.txt') if (p.parent/'exports').exists())
    if not (source/'exports').exists():raise ValueError('Expected extracted character pack with exports/')
    args.out.mkdir(parents=True,exist_ok=True)
    for name in ('README.txt','ASSET_CREDITS.txt'):
        shutil.copyfile(source/name,args.out/('SOURCE_'+name))
    command=[args.blender,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(Path(__file__).resolve()),'--',str(source),'--out',str(args.out.resolve()),'--worker','--only',*args.only]
    if args.preview:command.append('--preview')
    subprocess.run(command,check=True)
    provenance=dict(sourceArchiveSHA256=zip_sha,sourceFormat='User-provided Gujarat Desert Adventure v2 GLB exports',
                    converter=Path(__file__).name,blender=subprocess.check_output([args.blender,'--version'],text=True).splitlines()[0],
                    policy='Source scripts were inspected for rig documentation but never executed. All twenty-two original FK joints and top-four normalized skin influences are retained. Dense curves are decimated and excess disconnected fine hair strands thinned deterministically.',
                    textureBudget='Three 1024px RGB maps per character; 512px vest atlas region, 256px other textile regions; constant PBR factors packed in small cells.',
                    runtime='Compact little-endian manifest/binary geometry; no source GLB or Blender file bundled.',
                    animations='Source pack contains no animation clips. Original FK bind hierarchy is preserved for the game-authored driving, gunner and walking poses.',
                    adjustments='Driver source chest goggles are translated (0,+0.29,-0.05) in game coordinates and attached to head; all remaining clothing/hair/accessory proportions are preserved.',
                    characters={kind:json.loads((args.out/f'{kind}.json').read_text())['stats'] for kind in KINDS if (args.out/f'{kind}.json').exists()},
                    outputs={p.name:dict(bytes=p.stat().st_size,sha256=digest(p))for p in sorted(args.out.iterdir()) if p.is_file() and p.name!='PROVENANCE.json'})
    (args.out/'PROVENANCE.json').write_text(json.dumps(provenance,indent=2)+'\n')
    if task_tmp:task_tmp.cleanup()

if __name__=='__main__':main()
