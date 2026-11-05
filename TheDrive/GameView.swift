import SwiftUI
import SceneKit
import MetalKit

struct GameView: View {
    @StateObject private var game = GameModel()
    @StateObject private var graphics = GameGraphics()
    @State private var aimDragStart: CGPoint?
    @Environment(\.scenePhase) private var scenePhase
    private let sand = Color(red: 0.96, green: 0.78, blue: 0.48)

    var body: some View {
        ZStack {
            GameSceneView(game: game, graphics: graphics).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("THE DRIVE").font(.system(size: 22, weight: .black, design: .rounded)).tracking(5)
                        Text("DESERT / \(game.timeOfDay)").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(sand)
                    }
                    Spacer()
                    metric("DISTANCE", "\(game.distance) m")
                    metric("SCORE", "\(game.score)")
                    Button { game.toggleNight() } label: {
                        Image(systemName: game.isNight ? "moon.stars.fill" : "sun.max.fill").font(.title3).padding(12).background(.black.opacity(0.4), in: Circle())
                    }.accessibilityLabel("Toggle day and night").accessibilityValue(game.timeOfDay)
                }
                HStack {
                    Label(game.isGunning ? "REAR GUN · MANUAL AIM" : "DRIVING · KEEP MOVING", systemImage: game.isGunning ? "scope" : "steeringwheel")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(sand)
                    Spacer(minLength: 8)
                    if game.started && !game.isGameOver && !game.isCrashing { rearVision }
                    Spacer(minLength: 8)
                    Text("THREAT \(Int(game.nearestPursuer))m   JEEP").font(.system(size: 10, weight: .bold, design: .monospaced))
                    ProgressView(value: game.health).tint(game.health < 0.35 ? .red : sand).frame(width: 110)
                }
                if !game.warning.isEmpty {
                    Text(game.warning).font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(sand)
                }
                Spacer()
                if game.started && !game.isGameOver && !game.isCrashing {
                    HStack(alignment: .bottom, spacing: 18) {
                        if game.isGunning {
                            aimPad
                        } else {
                            HStack(spacing: 12) {
                                holdButton("arrow.left", label: "Steer left") { game.setSteering($0 ? -1 : 0) }
                                holdButton("arrow.right", label: "Steer right") { game.setSteering($0 ? 1 : 0) }
                            }.opacity(game.isTransitioning ? 0.3 : 1)
                        }
                        Spacer()
                        VStack(spacing: 8) {
                            Text(game.isGunning ? "LANE HOLD · DRAG TO AIM" : "SWITCH ON A CLEAR STRETCH")
                                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(sand)
                            Button { game.toggleGunner() } label: {
                                Label(game.isTransitioning ? "CHANGING POSITION" : game.isGunning ? "DRIVE" : "REAR GUN", systemImage: game.isGunning ? "steeringwheel" : "scope")
                                    .font(.system(size: 14, weight: .black, design: .rounded)).padding(.horizontal, 22).frame(height: 54)
                                    .background(sand, in: Capsule()).foregroundStyle(.black)
                            }.disabled(game.isTransitioning)
                        }
                        if game.isGunning {
                            VStack(spacing: 6) {
                                Button { game.reload() } label: {
                                    Text(game.isReloading ? "RELOADING…" : "\(game.ammo) / 24 · RELOAD")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                }.accessibilityLabel("Reload rear gun")
                                    .disabled(game.isTransitioning || game.isReloading)
                                holdButton("burst.fill", label: "Fire rear gun", accent: true) { game.setFiring($0) }
                                    .disabled(game.isTransitioning || game.isReloading)
                                    .opacity(game.isTransitioning || game.isReloading ? 0.35 : 1)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 28).padding(.vertical, 18)
            if !game.started || game.isGameOver { intro }
            if game.isCrashing {
                VStack {
                    Spacer()
                    Text("JEEP OVERTURNED")
                        .font(.system(size: 17, weight: .black, design: .rounded)).tracking(5)
                        .foregroundStyle(sand)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.black.opacity(0.6), in: Capsule())
                }.padding(.bottom, 25).allowsHitTesting(false)
            }
            if game.isGunning && game.started && !game.isGameOver && !game.isCrashing {
                GeometryReader { proxy in
                    ZStack {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 35 + CGFloat(game.recoil) * 9, weight: .ultraLight))
                        if game.hitMarker {
                            Image(systemName: "xmark").font(.system(size: 23, weight: .bold))
                        }
                    }
                    .foregroundStyle(game.hitMarker ? .white : sand.opacity(0.85))
                    .position(x: game.aimPoint.x * proxy.size.width, y: game.aimPoint.y * proxy.size.height)
                }.ignoresSafeArea().allowsHitTesting(false)
                    .opacity(game.isTransitioning ? 0 : 1)
            }
        }.foregroundStyle(.white)
        .onChange(of: scenePhase) { _, phase in
            game.setPaused(phase != .active)
        }
    }

    private var aimPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23).fill(.black.opacity(0.5))
            RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.25))
            Image(systemName: "scope").font(.system(size: 31, weight: .ultraLight)).foregroundStyle(sand)
            Text("DRAG TO AIM").font(.system(size: 9, weight: .bold, design: .monospaced)).offset(y: 36)
        }
        .frame(width: 144, height: 112)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !game.isTransitioning else { return }
                if aimDragStart == nil { aimDragStart = game.aimPoint }
                let start = aimDragStart ?? game.aimPoint
                game.setAim(CGPoint(x: start.x + value.translation.width / 340,
                                    y: start.y + value.translation.height / 260))
            }.onEnded { _ in aimDragStart = nil })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aim rear gun")
        .accessibilityValue("\(Int(game.aimPoint.x * 100)), \(Int(game.aimPoint.y * 100))")
    }

    /// Shared GPU texture; no image allocation or GPU-to-CPU readback on the game loop.
    private var rearVision: some View {
        VStack(spacing: 3) {
            if !game.isGunning {
                ReflectionSurface(graphics: graphics)
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: 184, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(white: 0.28), lineWidth: 4))
                    .shadow(color: .black.opacity(0.7), radius: 5, y: 3)
                Text("REAR VIEW").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
            } else if !game.isNight {
                ReflectionSurface(graphics: graphics)
                    .opacity(0.52)
                    .frame(width: 166, height: 39)
                    .clipShape(SunglassLenses())
                    .background(Color(red: 0.08, green: 0.15, blue: 0.13), in: SunglassLenses())
                    .overlay(SunglassLenses().stroke(sand.opacity(0.65), lineWidth: 2))
                    .overlay(Rectangle().fill(sand).frame(width: 9, height: 2))
                Text("SUNGLASSES · ROAD AHEAD").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(sand)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "eyeglasses").font(.title2).opacity(0.3)
                    Text("NO REFLECTION AT NIGHT").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                }.frame(width: 184, height: 59)
            }
        }.allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(graphics.reflectionReady ? "Live" : "Unavailable")
            .accessibilityLabel(!game.isGunning ? "Live rear view mirror" : game.isNight ? "Sunglass reflection unavailable at night" : "Daytime sunglass road reflection")
    }

    private var intro: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 15) {
                Text(game.isGameOver ? "END OF THE ROAD" : "THE DRIVE").font(.system(size: 42, weight: .black, design: .rounded)).tracking(5)
                Text(game.isGameOver ? "\(game.distance) METERS  /  \(game.score) POINTS" : "AN ENDLESS DESERT ESCAPE").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(sand)
                Text(game.isGameOver ? "The pursuit caught up. Find another way through." : "Dodge late to bait pursuers into wrecks.\nSwitch to the gun, drag the left pad to aim, and hold fire.\nEnemies dodge your shots. Reload and return to driving before hazards.")
                    .font(.system(size: 14)).multilineTextAlignment(.center).lineSpacing(5).foregroundStyle(.white.opacity(0.85))
                Button { game.isGameOver ? game.restart() : game.start() } label: {
                    Text(game.isGameOver ? "TRY ANOTHER ROUTE" : "HIT THE ROAD").font(.system(size: 15, weight: .black, design: .rounded)).tracking(2)
                        .padding(.horizontal, 34).padding(.vertical, 17).background(sand, in: Capsule()).foregroundStyle(.black)
                }.padding(.top, 6)
                Text("PROCEDURAL ROUTE · SEED \(String(game.seed, radix: 16).uppercased())").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            }.padding(30)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(sand)
            Text(value).font(.system(size: 21, weight: .bold, design: .monospaced)).monospacedDigit()
        }.padding(.horizontal, 8)
    }

    private func holdButton(_ symbol: String, label: String, accent: Bool = false, action: @escaping (Bool) -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 26, weight: .bold)).frame(width: 68, height: 62)
            .background(accent ? sand.opacity(0.85) : Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.3)))
            .foregroundStyle(accent ? .black : .white)
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in action(true) }.onEnded { _ in action(false) })
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .onDisappear { action(false) }
    }
}

private struct SunglassLenses: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gap: CGFloat = 8
        let width = (rect.width - gap) / 2
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: width, height: rect.height), cornerSize: CGSize(width: 12, height: 12))
        path.addRoundedRect(in: CGRect(x: width + gap, y: 0, width: width, height: rect.height), cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}

@MainActor
private final class GameGraphics: NSObject, ObservableObject, MTKViewDelegate {
    @Published private(set) var reflectionReady = false
    let device = MTLCreateSystemDefaultDevice()
    weak var surface: MTKView?
    private var renderer: SCNRenderer?
    private var queue: MTLCommandQueue?
    private var textures: [MTLTexture] = []
    private var depth: MTLTexture?
    private var slot = 0
    private var inFlight = false
    private var lastRender: TimeInterval = 0
    private var renderSceneTime: TimeInterval = 0
    private weak var renderGame: GameModel?
    private var generation = 0
    private var captureState: CaptureState?
    private struct CaptureState: Equatable {
        let seed: UInt64
        let gunning: Bool
        let night: Bool
    }
    private let size = CGSize(width: 384, height: 112)

    func configure(game: GameModel) {
        guard renderer == nil, let device else { return }
        queue = device.makeCommandQueue()
        renderer = SCNRenderer(device: device, options: nil)
        renderer?.scene = game.scene
        renderer?.isPlaying = false
        renderer?.usesReverseZ = true
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        textures = (0..<3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        depth = device.makeTexture(descriptor: depthDescriptor)
    }

    func draw(game: GameModel, time: TimeInterval, sceneTime: TimeInterval) {
        let state = CaptureState(seed: game.seed, gunning: game.isGunning, night: game.isNight)
        if state != captureState {
            captureState = state
            generation += 1
            reflectionReady = false
        }
        let interval: TimeInterval = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical ? 1.0 / 12 : 1.0 / 20
        guard game.started, !game.isPaused, !game.isGameOver, !game.isCrashing, !game.isTransitioning,
              (!game.isGunning || !game.isNight), !inFlight,
              time - lastRender >= interval, let surface else { return }
        lastRender = time
        renderSceneTime = sceneTime
        renderGame = game
        surface.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in surface: MTKView) {
        guard let game = renderGame, !game.isPaused, !game.isGameOver, !game.isCrashing, !inFlight,
              textures.count == 3, let drawable = surface.currentDrawable,
              let renderer, let command = queue?.makeCommandBuffer() else { return }
        inFlight = true
        let textureIndex = slot
        let texture = textures[textureIndex]
        slot = (slot + 1) % textures.count
        renderer.pointOfView = game.isGunning ? game.roadCameraNode : game.rearCameraNode
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.02, 0.025, 0.04, 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 0
        renderer.render(atTime: renderSceneTime, viewport: CGRect(origin: .zero, size: size), commandBuffer: command, passDescriptor: pass)
        if let blit = command.makeBlitCommandEncoder() {
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: 384, height: 112, depth: 1),
                      to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }
        command.present(drawable)
        let generation = generation
        let rendererIdentity = ObjectIdentifier(renderer)
        command.addCompletedHandler { [weak self, weak game] buffer in
            let succeeded = buffer.status == .completed
            Task { @MainActor in
                guard let self else { return }
                guard let currentRenderer = self.renderer else { return }
                let sameRenderer = ObjectIdentifier(currentRenderer) == rendererIdentity
                if sameRenderer { self.inFlight = false }
                guard self.generation == generation, sameRenderer, succeeded,
                      self.textures.indices.contains(textureIndex),
                      let game, !game.isPaused, !game.isGameOver, !game.isCrashing else { return }
                if !self.reflectionReady { self.reflectionReady = true }
                game.updateReflectionTexture(self.textures[textureIndex])
            }
        }
        command.commit()

    }

    func stop() {
        generation += 1
        captureState = nil
        inFlight = false
        lastRender = 0
        renderer?.scene = nil
        renderer = nil
        queue = nil
        textures.removeAll()
        depth = nil
        reflectionReady = false
    }
}

private struct ReflectionSurface: UIViewRepresentable {
    let graphics: GameGraphics
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: graphics.device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 384, height: 112)
        view.clearColor = MTLClearColorMake(0.02, 0.025, 0.04, 1)
        view.delegate = graphics
        graphics.surface = view
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) { graphics.surface = view }
}

/// SceneKit's Metal renderer can reverse depth; keep aim consistent with either projection.
@MainActor
enum AimProjection {
    static func ray(in view: SCNView, at normalizedPoint: CGPoint) -> (origin: SCNVector3, direction: SCNVector3) {
        let x = Float(normalizedPoint.x * view.bounds.width)
        let y = Float(normalizedPoint.y * view.bounds.height)
        let zero = view.unprojectPoint(SCNVector3(x, y, 0))
        let one = view.unprojectPoint(SCNVector3(x, y, 1))
        let camera = view.pointOfView?.worldPosition ?? SCNVector3Zero
        func squaredDistance(_ point: SCNVector3) -> Float {
            let dx = point.x - camera.x, dy = point.y - camera.y, dz = point.z - camera.z
            return dx * dx + dy * dy + dz * dz
        }
        // SCNView may normalize its public projection API even with a reversed GPU depth buffer.
        let near = squaredDistance(zero) < squaredDistance(one) ? zero : one
        let far = squaredDistance(zero) < squaredDistance(one) ? one : zero
        return (near, SCNVector3(far.x - near.x, far.y - near.y, far.z - near.z))
    }
}

private struct GameSceneView: UIViewRepresentable {
    let game: GameModel
    let graphics: GameGraphics
    func makeCoordinator() -> Coordinator { Coordinator(game: game, graphics: graphics) }
    func makeUIView(context: Context) -> SCNView {
        var options: [String: Any] = [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue]
        if let device = graphics.device { options[SCNView.Option.preferredDevice.rawValue] = device }
        let view = SCNView(frame: .zero, options: options)
        view.scene = game.scene
        view.pointOfView = game.cameraNode
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.backgroundColor = .black
        graphics.configure(game: game)
        context.coordinator.start(view: view)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        view.isPlaying = !game.isPaused
        view.scene?.isPaused = game.isPaused
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject {
        let game: GameModel
        let graphics: GameGraphics
        var link: CADisplayLink?
        private weak var view: SCNView?
        init(game: GameModel, graphics: GameGraphics) { self.game = game; self.graphics = graphics }
        func start(view: SCNView) {
            self.view = view
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        func stop() {
            link?.invalidate(); link = nil
            graphics.stop()
        }
        @objc func tick(_ link: CADisplayLink) {
            if let view, game.isGunning, !game.isTransitioning, !game.isCrashing, view.bounds.width > 0 {
                let ray = AimProjection.ray(in: view, at: game.aimPoint)
                game.setAimRay(origin: ray.origin, direction: ray.direction)
            }
            game.update(time: link.timestamp)
            graphics.draw(game: game, time: link.timestamp, sceneTime: view?.sceneTime ?? link.timestamp)
        }
    }
}
