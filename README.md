# The Drive

A native iOS 3D endless escape game built with SwiftUI and SceneKit. Play as an Indian driver escaping a fictional local gang. Drive an old jeep through a procedurally generated ruined desert town, bait pursuers into obstacles, and switch to the rear-mounted gun when the road is clear.

## Play

1. Open `TheDrive.xcodeproj` in Xcode.
2. Select the **TheDrive** scheme and an iPhone simulator, then press **Run**.
3. Rotate to landscape if needed and tap **HIT THE ROAD**.

For a physical iPhone, select your device and set your development team in the target's **Signing & Capabilities** settings before running. Requires Xcode with the iOS SDK and iOS 17 or later. No external packages or runtime downloads are required. The licensed humanoid and vehicle meshes are bundled with the app; see [asset credits](THIRD_PARTY_ASSETS.md).

## Controls

- Hold the left or right arrow to steer; release to stop steering.
- Tap **REAR GUN**. The same character climbs out of the front seat, turns around, and takes the gun over 1.1 seconds. Firing is locked during the transfer.
- In gun mode, drag the left aim pad to move the reticle and hold the right fire button. Shots follow the reticle in world space: there is no automatic targeting. Bikes juke fastest, rally cars swerve, and heavy trucks dodge slowly.
- Each magazine holds 24 rounds, with a 1.5-second reload. Tap the ammunition display to reload early. Recoil raises the reticle, so pull down to compensate.
- Tap **DRIVE** to climb back into the seat. The Jeep maintains its lane and forward speed while you use the gun; it does not automatically avoid obstacles.
- The live rear-view mirror shows approaching pursuers while driving, during day and night.
- In daylight gun mode, the driver's sunglasses provide a faint forward-road preview. This reflection is unavailable at night.
- Daylight cycles automatically through sunset, night and morning every two minutes of active play. The first night starts after roughly half a minute. Pausing freezes the clock. Tap the sun/moon button to skip to day or night; the cycle then continues.
- The seeded road has rolling hills, bumps, potholes and banked shoulders. Each tire samples the visible road surface, with filtered body pitch, roll and camera movement.
- Dodge road hazards late to trick pursuers into rollovers. Bikes, rally cars, and armored vehicles have different handling and durability.
- Avoid crossing pedestrians and wreckage. If the pursuers catch you or the jeep is destroyed, the run ends.
- Tap **TRY ANOTHER ROUTE** to start again with a new route seed.

## Structure

- `TheDrive/GameModel.swift`: game state, movement, pursuit, shooting, collisions, and endless recycling.
- `TheDrive/WorldBuilder.swift`: imported houses and vehicles, seeded environment districts, road meshes, materials, and lighting.
- `TheDrive/DayCycle.swift`: continuous solar phases and daylight.
- `TheDrive/RoadSurface.swift`: seeded surface heights, four-wheel contact fitting, and suspension filtering.
- `TheDrive/GameView.swift`: touch controls, HUD, start/retry screens, and SceneKit host.
- `TheDrive/TheDriveApp.swift`: app entry point.

The prototype uses procedural geometry and arcade movement rather than a full vehicle physics simulation. All game-state updates run on the main actor.

To build from Terminal without device signing:

```sh
xcodebuild -project TheDrive.xcodeproj -scheme TheDrive -sdk iphonesimulator -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Run the simulation tests on an installed simulator (replace the device name if needed):

```sh
xcodebuild -project TheDrive.xcodeproj -scheme TheDrive -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO test
```

Tests cover pause/resume timing, rear-gun combat and scoring, contiguous recycled road tiles, reproducible route geometry, day/night lights, and restart state.

## Validation

Built and launched on the iPhone 18 Pro simulator with Xcode 27.2 / iOS 27.2. Thirty simulation and projection tests cover manual hits and misses, evasive steering, transfers, reload timing, paused state, the imported skin rig, camera projection, procedural generation, and bounded resources over repeated seeded runs, crash trajectories, paused rollovers, delayed player game-over, the imported cars’ steering wheels, automatic daylight phases, terrain mesh alignment and seamless chunk boundaries. Three UI smoke tests cover the live mirror, manual aim/fire/seat return, and night behavior. Screenshots are retained in the Xcode test result attachments.

The visuals use procedural textured geometry, physically based paint and metal, day/night environment reflections, detailed treads and vehicle fittings, transparent windscreens, suspension bounce, and bounded dust particles. Shared 512-pixel surface textures are generated once and cached. A triple-buffered Metal pass renders the 384×112 mirror and sunglass view at up to 20 fps (12 under thermal pressure), then presents and samples those GPU textures directly. The game loop no longer takes UIImage snapshots or waits for GPU-to-CPU readback. The main view and simulation target 60 fps. Scenery is batched by shared materials, wheel geometry and surface images are cached, and bullets reuse a fixed pool of twelve tracer nodes.

Rally cars and SUVs use bundled Kenney vehicle meshes with independent wheels, steering, filtered body lean, and integrated tire rotation. Vehicles that hit roadblocks or lunge onto the broken shoulder can launch, tumble, bounce, and slide into a wreck. Crash motion uses simulation time, pauses correctly, and caps active wrecks at eight; a fatal Jeep impact plays its rollover before showing retry. The route remains endless.

Six authored Kenney house models replace the original box houses, with porch, chimney and roof variety, damaged variants, fences and terrain-supported foundations. Seeded sections vary between village streets, ruined compounds, sparse outskirts and open desert. Window emission, street lamps and headlights fade with the solar cycle; sky blending uses at most 33 small cached maps with one unchanged reflection-lighting map.

The hero and pursuers use a smooth, skinned Quaternius human mesh with articulated knees and elbows instead of box-built bodies. The art style remains stylized rather than photorealistic. The updated app builds with development signing and installs on the connected iPhone 16. Sustained frame rate and thermal behavior still need a longer play session on the phone.

![Driving with live rear-view mirror](docs/rear-mirror.png)

![Rear gun gameplay](docs/rear-gun.png)

![Night driving](docs/night-driving.png)

![Rollover pose preview with the imported rally car](docs/car-rollover.png)
