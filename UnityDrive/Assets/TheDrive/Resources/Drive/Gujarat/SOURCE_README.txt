GUJARAT DESERT ADVENTURE — VERSION 2
==================================
Three editable Blender characters, created for the Gujarat desert driving
and adventure-game concept. All three are adults. No guns are included.

This version combines continuous sculpted anatomical meshes with separately
editable hair, layered clothing, travel equipment, footwear and body rigs.
It was built with Blender 4.3.2. The Blender scene is the most complete version
of the characters and their materials.

CHARACTERS
----------
Driver
  Curly-haired young adult man in a gathered kediyu-inspired cotton tunic,
  padded embroidered vest and folded bandhani scarf. Driving goggles,
  a small travel pouch, water flask, reinforced trousers and leather boots.

Explorer
  Adult woman with braided hair, a fitted split tunic, rust embroidered vest
  and bandhani wrap. A crossbody leather satchel, rolled field map, compass,
  practical trousers and constructed boots support her explorer role.

Grandpa
  Older man with white hair and a completely clean-shaven face. A long kurta,
  cream embroidered vest, deeply folded dhoti, draped crimson shouldercloth
  and sturdy boots distinguish his silhouette.

OPEN AND EDIT
-------------
1. Open Gujarat_Desert_Characters.blend in Blender 4.3.2, or a compatible
   newer version. Opening the scene does not require additional add-ons.
2. Each character has its own collection in the Outliner. Hide the other
   character collections to inspect or edit one model.
3. Clothing, hair and accessories are separate named mesh objects. The skin
   foundation uses continuous sculpted heads/necks and exposed forearm/hand
   geometry, including facial forms and detailed fingers.
4. The STUDIO collection contains the ground, lights and cameras used for
   presentation. These objects are excluded from the individual GLB exports.

Image textures are packed into the .blend. The corresponding source PNGs are
also included in textures_v2/. Keep the extracted folder structure intact
if you intend to rebuild the project from its scripts.

ANATOMICAL FOUNDATION AND CREDITS
--------------------------------
The anatomical foundation is derived from Blender Studio and community
contributors' Human Base Meshes v1.4.1, published under CC0. The donor meshes
are fitted and differentiated for these characters; clothing, equipment,
hairstyles, materials, basic rigging and scene setup are specific to this
project. See ASSET_CREDITS.txt for the source and official links.

assets_v2/anatomy_donors_v2.npz contains the extracted donor data used by the
rebuild script. The complete upstream asset bundle is not needed for a normal
rebuild with this cache present.

MATERIALS
---------
Textiles and leather use authored 2K (2048 x 2048) PBR image maps. Depending on
material, these include color, roughness, normal, height-source and metallic
maps. The vest textures use a single authored panel with embroidery borders,
rosettes, small motifs and restrained mirrorwork. Garment folds, padding,
hems and construction details are also represented in the mesh geometry.

The Blender materials additionally use procedural skin pigmentation, pores,
hair shading and cornea effects. These features are intended for the .blend
scene and its renders.

The GLB files use simpler PBR approximations for the complex Blender skin,
hair and cornea materials. Their appearance can differ from the Blender
renders, particularly in skin detail, hair highlights and eye refraction.
The image-based textile materials and their embedded maps are retained.

POSING AND RIG LIMITS
--------------------
Each character has a separate basic 22-bone forward-kinematics (FK) body rig.
Select its 'Pose Rig' in the Outliner, enter Pose Mode, and rotate body bones.
Alt+R and Alt+G clear pose rotations and translations in Blender. The scene
opens with restrained, asymmetric presentation poses.

There are no facial controls, finger controls, inverse-kinematics (IK)
controls or animation clips. Clothing is modeled rather than dynamically
simulated. Large joint rotations can require weight painting and clothing
intersection cleanup. The rigs support inspection and basic body posing;
they have not been validated as production animation rigs.

GAME USE AND GEOMETRY
---------------------
These are dense presentation meshes. The sculpted skin, modeled hair and
cloth construction carry substantial geometry. They require a game-asset
optimization pass before real-time use, especially on mobile hardware.

For a production game, plan for retopology or controlled decimation, baking
surface detail, mesh/material consolidation, level-of-detail (LOD) models,
platform-specific texture budgets and animation/deformation testing.
model_stats.json records the evaluated mesh, vertex, triangle and bone counts
for the delivered scene; consult it for the actual geometry budget.

EXPORTS
-------
exports/driver.glb
exports/explorer.glb
exports/grandpa.glb

Each file contains one character at its local origin with its body skeleton
and embedded image textures. Studio objects are excluded. Blender source
coordinates use metres, Z up and -Y forward; GLB uses the Y-up convention.
No animation clips are included in the exports.

RENDERED PREVIEWS
-----------------
previews/character_lineup.png       Full three-character lineup.
previews/character_details.png      Close view of faces and upper clothing.
previews/character_rear.png         Rear view of the complete characters.

When present, the following are individual portrait renders:
previews/driver_portrait.png
previews/explorer_portrait.png
previews/grandpa_portrait.png

All preview images are rendered from the modeled geometry in Blender.

REBUILD AND SOURCE FILES
-----------------------
scripts/build_scene_v2.py       Scene construction, rigging, posing and export.
scripts/export_assets_v2.py     Re-export an edited .blend without rebuilding.
scripts/anatomy_v2.py           Fitted sculpted anatomy, hair and skin detail.
scripts/wardrobe_v2.py          Cloth volumes, garments, boots and accessories.
scripts/materials_v2.py         Original surface maps and Blender materials.
scripts/render_details_v2.py    Detail, rear and optional portrait renders.
scripts/verify_scene.py         Checks the delivered Blender scene.
scripts/verify_exports.py       Checks the three exported GLB files.
scripts/package_assets_v2.py    Creates the whitelisted deliverable archive.
textures_v2/                   Included 2K PNG material maps and height sources.
assets_v2/anatomy_donors_v2.npz Included extracted CC0 anatomical donor cache.

Run these commands from the extracted project folder:

  Rebuild the scene, export the characters and render the lineup:
    blender -b --factory-startup --python scripts/build_scene_v2.py

  Rebuild a draft preview:
    blender -b --factory-startup --python scripts/build_scene_v2.py -- --draft

  Rebuild geometry and exports without rendering:
    blender -b --factory-startup --python scripts/build_scene_v2.py -- --no-render

  Re-export the characters after editing and saving the Blender scene:
    blender -b Gujarat_Desert_Characters.blend --python scripts/export_assets_v2.py

  Render close-ups, rear view and individual portraits from the final scene:
    blender -b Gujarat_Desert_Characters.blend --python scripts/render_details_v2.py -- --portraits

The supplied PNG maps and donor cache allow the geometry rebuild to use the
included local assets. Regenerating the authored PNG texture maps requires
ordinary Python with NumPy, Pillow and SciPy. These separate Python packages
are not needed merely to open the finished .blend. The scene renderer uses
CPU Cycles with denoising disabled for compatibility with this Blender build.

ARCHIVE INTEGRITY
-----------------
manifest.json lists the byte size and SHA-256 checksum of every payload file
in the package. The manifest itself is excluded from its own checksum list.
The package script uses an explicit whitelist so drafts, backup .blend files,
source downloads, diagnostic scenes and previous-version assets are omitted.
