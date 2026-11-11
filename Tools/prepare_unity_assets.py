#!/usr/bin/env python3
"""Stage existing optimized game assets for Unity; never re-decimates source meshes.

JSON becomes *-manifest.json and .bin becomes *-buffer.bytes. Unique basenames
are essential because Unity Resources keys do not include the file extension. PNG UVs
already use bottom-origin coordinates, matching Unity: do not flip the atlas.
Metallic(B)/roughness(G) maps are repacked for Standard's metallic(R)/smoothness(A).
"""
from pathlib import Path
import json
import shutil
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'TheDrive/Assets'
DST = ROOT / 'UnityDrive/Assets/TheDrive/Resources/Drive'

def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

def main():
    # Remove only this script's previous ambiguous JSON/binary resource names.
    # Both extensions import as TextAsset, so their shared Resources keys were invalid.
    old_keys = ['JeepBody', 'EnvironmentMesh', 'Vehicle-suv', 'Vehicle-bike', 'Vehicle-hatchback-sports']
    old_keys += ['Vehicle-suv-colors', 'Vehicle-bike-colors', 'Vehicle-hatchback-sports-colors']
    old_keys += [f'Gujarat/{kind}' for kind in ['driver', 'explorer', 'grandpa']]
    for key in old_keys:
        for extension in ['json', 'bytes']:
            old = DST / f'{key}.{extension}'
            for file in [old, Path(str(old) + '.meta')]:
                if file.exists(): file.unlink()
    for name in ['JeepBody', 'EnvironmentMesh', 'Vehicle-suv', 'Vehicle-bike', 'Vehicle-hatchback-sports']:
        for ext in ['json', 'bin']:
            copy(SRC / f'{name}.{ext}', DST / f'{name}-{"buffer.bytes" if ext == "bin" else "manifest.json"}')
        colors = SRC / f'{name}-colors.bin'
        if colors.exists(): copy(colors, DST / f'{name}-colors-buffer.bytes')
    for kind in ['driver', 'explorer', 'grandpa']:
        manifest = json.loads((SRC / f'Gujarat/{kind}.json').read_text())
        data = (SRC / f'Gujarat/{kind}.bin').read_bytes()
        assert len(manifest['joints']) == 22
        for mesh in manifest['meshes']:
            for field, stride in [('positions',12),('normals',12),('uv',8),('joints',8),('weights',16)]:
                s=mesh[field]; assert 0 <= s['offset'] and s['offset']+s['count']*stride <= len(data)
        for ext in ['json', 'bin']:
            copy(SRC/f'Gujarat/{kind}.{ext}', DST/f'Gujarat/{kind}-{"buffer.bytes" if ext == "bin" else "manifest.json"}')
        for suffix in ['color','normal','metallic-roughness']:
            copy(SRC/f'Gujarat/{kind}-{suffix}.png', DST/f'Gujarat/{kind}-{suffix}.png')
        image=Image.open(SRC/f'Gujarat/{kind}-metallic-roughness.png').convert('RGB')
        r,g,b=image.split()
        Image.merge('RGBA',(b,Image.new('L', image.size,0),Image.new('L', image.size,0),g.point(lambda x:255-x))).save(DST/f'Gujarat/{kind}-standard-metallic.png')
    for name in ['SOURCE_README.txt','SOURCE_ASSET_CREDITS.txt','PROVENANCE.json']:
        copy(SRC/'Gujarat'/name,DST/'Gujarat'/name)
    for name in ['KENNEY_LICENSE.txt','QUATERNIUS_LICENSE.txt']:
        copy(SRC/name,DST/name)
    for source,name in [('AppIcon.appiconset/AppIcon.png','AppIcon.png'),('LaunchArtwork.imageset/LaunchArtwork.png','LaunchArtwork.png')]:
        copy(ROOT/'TheDrive/GameArt.xcassets'/source, DST/'Art'/name)
    print(f'Staged optimized Unity assets: {sum(p.stat().st_size for p in DST.rglob("*") if p.is_file())/1048576:.1f} MiB')

if __name__ == '__main__': main()
