import AVFoundation
import Combine
import Foundation

/// Audio is prepared at a common tempo offline. Runtime work only reads a few bars at a time.
struct SoundtrackTrack: Equatable {
    let id: String
    let resource: String
    let firstDownbeat: Double
    let bpm: Double
    let duration: Double

    var framesPerBar: Double { SoundtrackPlanner.sampleRate * 240 / bpm }
    var availableBars: Int {
        guard bpm.isFinite, bpm > 0, duration.isFinite, firstDownbeat.isFinite,
              firstDownbeat >= 0, duration > firstDownbeat + SoundtrackCrossfade.duration else { return 0 }
        return max(0, Int(((duration - firstDownbeat - SoundtrackCrossfade.duration)
                          * SoundtrackPlanner.sampleRate / framesPerBar).rounded(.down)))
    }

    // Measured source grids and normalization details are retained beside these files.
    static let bundled: [SoundtrackTrack] = [
        SoundtrackTrack(id: "thavil-tavil-fusion", resource: "ThavilTavilFusion", firstDownbeat: 0,
                        bpm: 97, duration: 117.6106666667),
        SoundtrackTrack(id: "chant", resource: "Chant", firstDownbeat: 0,
                        bpm: 97, duration: 64.4266666667)
    ]
}

struct SoundtrackPiece: Equatable {
    let trackIndex: Int
    let startBar: Int
    let barCount: Int
    let sourceStartFrame: Int64
    let frameCount: UInt32
    let timelineStartFrame: Int64
}

/// Stable SplitMix64 choices deliberately do not consume the route's gameplay random stream.
struct SoundtrackPlanner {
    static let sampleRate = 48_000.0
    let tracks: [SoundtrackTrack]
    private var state: UInt64
    private var timeline: Int64 = 0
    private var previous: SoundtrackPiece?
    private var consecutiveTrackCount = 0
    private var totalBars = 0

    init(seed: UInt64, tracks: [SoundtrackTrack] = SoundtrackTrack.bundled) {
        self.tracks = tracks
        state = seed ^ 0x6D757369635F6D78
    }

    mutating func next() -> SoundtrackPiece? {
        guard let first = tracks.first, first.availableBars > 0,
              tracks.allSatisfy({ $0.availableBars > 0 && abs($0.bpm - first.bpm) < 0.0001 }) else { return nil }
        var index = Int(random() % UInt64(tracks.count))
        if let previous, tracks.count > 1,
           consecutiveTrackCount >= 2 || random() % 4 != 0 {
            // Always progress to a different song after two pieces; usually switch sooner.
            index = (previous.trackIndex + 1 + Int(random() % UInt64(tracks.count - 1))) % tracks.count
        }
        let track = tracks[index]
        let lengths = [1, 2, 4, 8].filter { $0 <= track.availableBars }
        let bars = lengths[Int(random() % UInt64(lengths.count))]
        let startCount = track.availableBars - bars + 1
        var start = Int(random() % UInt64(startCount))
        if let previous, previous.trackIndex == index, previous.startBar == start, startCount > 1 {
            start = (start + 1) % startCount
        }
        let end = Int64((Double(totalBars + bars) * first.framesPerBar).rounded())
        let sourceStart = Int64((track.firstDownbeat * Self.sampleRate + Double(start) * track.framesPerBar).rounded())
        let piece = SoundtrackPiece(trackIndex: index, startBar: start, barCount: bars,
                                    sourceStartFrame: sourceStart, frameCount: UInt32(end - timeline),
                                    timelineStartFrame: timeline)
        consecutiveTrackCount = previous?.trackIndex == index ? consecutiveTrackCount + 1 : 1
        previous = piece
        totalBars += bars
        timeline = end
        return piece
    }

    private mutating func random() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

enum SoundtrackCrossfade {
    static let duration = 0.04
    static let frameCount = Int(SoundtrackPlanner.sampleRate * duration)

    static func gains(progress: Float) -> (outgoing: Float, incoming: Float) {
        let angle = min(1, max(0, progress)) * .pi / 2
        return (cos(angle), sin(angle))
    }
}

@MainActor
final class Soundtrack: ObservableObject {
    static let trackTitles = ["Thavil Tavil Fusion", "chant"]
    @Published private(set) var isAvailable: Bool
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "Music ready"
    @Published private(set) var isMuted = false

    private let playback = SoundtrackPlayback()
    private var observers: [NSObjectProtocol] = []
    private var activeSeed: UInt64?
    private var wantsPaused = false
    private var interrupted = false
    private var playbackReady = false
    private var requestGeneration = 0
    private var routeSuspended = false

    init() {
        isAvailable = SoundtrackTrack.bundled.allSatisfy { Self.url(for: $0) != nil }
        if !isAvailable { status = "Music files unavailable" }
        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let seed = self.activeSeed else { return }
                let paused = self.wantsPaused
                self.start(seed: seed)
                self.setPaused(paused)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                self.routeSuspended = true
                self.playback.setPaused(true)
                self.isPlaying = false
            }
        })
        #endif
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        playback.stop()
    }

    func start(seed: UInt64) {
        requestGeneration += 1
        let request = requestGeneration
        playbackReady = false
        isPlaying = false
        routeSuspended = false
        activeSeed = seed
        wantsPaused = false
        interrupted = false
        guard isAvailable else { status = "Music files unavailable"; return }
        do { try activateSession() }
        catch { status = "Music unavailable"; isPlaying = false; return }
        let urls = SoundtrackTrack.bundled.compactMap { Self.url(for: $0) }
        status = "Mixing both tracks"
        playback.start(seed: seed, urls: urls, muted: isMuted) { [weak self] success in
            Task { @MainActor in
                guard let self, self.requestGeneration == request else { return }
                self.playbackReady = success
                self.isPlaying = success && !self.wantsPaused && !self.interrupted && !self.routeSuspended
                self.status = success ? "Seeded bar mix" : "Music unavailable"
            }
        }
    }

    func setPaused(_ value: Bool) {
        wantsPaused = value
        if !value { routeSuspended = false }
        guard activeSeed != nil else { return }
        if !value && !interrupted {
            do { try activateSession() }
            catch { status = "Music unavailable"; playbackReady = false; isPlaying = false; return }
        }
        playback.setPaused(value || interrupted)
        isPlaying = playbackReady && !value && !interrupted
    }

    func setMuted(_ value: Bool) {
        isMuted = value
        playback.setMuted(value)
        if !value && routeSuspended { setPaused(wantsPaused) }
    }

    func stop() {
        requestGeneration += 1
        playbackReady = false
        activeSeed = nil
        playback.stop()
        isPlaying = false
        status = isAvailable ? "Music ready" : "Music files unavailable"
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private static func url(for track: SoundtrackTrack) -> URL? {
        Bundle.main.url(forResource: track.resource, withExtension: "m4a", subdirectory: "Assets/Music")
    }

    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }

    #if os(iOS)
    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            interrupted = true
            playback.setPaused(true)
            isPlaying = false
        } else {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            interrupted = !shouldResume
            if shouldResume { setPaused(wantsPaused) }
        }
    }
    #endif
}

/// A serial worker owns decoding and the audio graph. Three queued PCM pieces bound memory to
/// about 25 MB of queued audio. The player schedules adjacent buffers on its sample clock, independent of UI FPS.
private final class SoundtrackPlayback {
    private let queue = DispatchQueue(label: "com.thedrive.soundtrack", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var renderer: SoundtrackPCMRenderer?
    private var planner: SoundtrackPlanner?
    private var generation = 0
    private var paused = false
    private var queued = 0
    private var completion: ((Bool) -> Void)?

    func start(seed: UInt64, urls: [URL], muted: Bool, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            tearDown()
            self.completion = completion
            let token = generation
            do {
                let renderer = try SoundtrackPCMRenderer(urls: urls)
                self.renderer = renderer
                let graph = AVAudioEngine()
                let node = AVAudioPlayerNode()
                graph.attach(node)
                graph.connect(node, to: graph.mainMixerNode, format: renderer.format)
                graph.mainMixerNode.outputVolume = muted ? 0 : 0.65
                engine = graph; player = node; planner = SoundtrackPlanner(seed: seed)
                for _ in 0..<3 { try scheduleNext(token: token) }
                graph.prepare()
                try graph.start()
                if !paused { node.play() }
                completion(true)
            } catch {
                tearDown()
                completion(false)
            }
        }
    }

    func setPaused(_ value: Bool) {
        queue.async { [self] in
            paused = value
            guard let engine, let player else { return }
            if value { player.pause(); engine.pause() }
            else {
                do { try engine.start(); player.play() }
                catch { completion?(false) }
            }
        }
    }

    func setMuted(_ value: Bool) {
        queue.async { [self] in engine?.mainMixerNode.outputVolume = value ? 0 : 0.65 }
    }

    func stop() { queue.async { [self] in tearDown() } }

    private func tearDown() {
        generation += 1
        player?.stop(); engine?.stop()
        player = nil; engine = nil; renderer = nil; planner = nil
        queued = 0; paused = false; completion = nil
    }

    private func scheduleNext(token: Int) throws {
        guard token == generation, let piece = planner?.next(), let player else { return }
        guard let renderer else { return }
        let output = try renderer.render(piece)
        queued += 1
        player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard token == self.generation else { return }
                self.queued -= 1
                do { try self.scheduleNext(token: token) }
                catch { self.completion?(false); self.tearDown() }
            }
        }
    }

}


/// Shared by live playback and offline verification. Keeps only a 40 ms outgoing tail.
final class SoundtrackPCMRenderer {
    let format: AVAudioFormat
    private let files: [AVAudioFile]
    private var tail: [[Float]]?

    init(urls: [URL]) throws {
        files = try urls.map { try AVAudioFile(forReading: $0, commonFormat: .pcmFormatFloat32, interleaved: false) }
        guard let first = files.first, files.count == SoundtrackTrack.bundled.count,
              files.allSatisfy({ $0.processingFormat.sampleRate == SoundtrackPlanner.sampleRate && $0.processingFormat.channelCount == 2 }) else {
            throw RenderError.invalidFormat
        }
        format = first.processingFormat
    }

    func render(_ piece: SoundtrackPiece) throws -> AVAudioPCMBuffer {
        guard files.indices.contains(piece.trackIndex) else { throw RenderError.invalidFormat }
        let file = files[piece.trackIndex]
        let extra = SoundtrackCrossfade.frameCount
        let count = Int(piece.frameCount)
        guard count >= extra, piece.sourceStartFrame >= 0,
              piece.sourceStartFrame + Int64(count + extra) <= file.length,
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count + extra)),
              let output = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: piece.frameCount) else {
            throw RenderError.invalidFormat
        }
        file.framePosition = piece.sourceStartFrame
        try file.read(into: source, frameCount: AVAudioFrameCount(count + extra))
        guard Int(source.frameLength) == count + extra,
              let input = source.floatChannelData, let result = output.floatChannelData else { throw RenderError.invalidFormat }
        output.frameLength = piece.frameCount
        var nextTail = [[Float]]()
        for channel in 0..<2 {
            result[channel].update(from: input[channel], count: count)
            if let tail {
                for frame in 0..<extra {
                    let gain = SoundtrackCrossfade.gains(progress: Float(frame) / Float(extra - 1))
                    result[channel][frame] = tail[channel][frame] * gain.outgoing + input[channel][frame] * gain.incoming
                }
            } else {
                let introFade = min(extra, 240)
                for frame in 0..<introFade { result[channel][frame] *= Float(frame) / Float(introFade - 1) }
            }
            nextTail.append(Array(UnsafeBufferPointer(start: input[channel].advanced(by: count), count: extra)))
        }
        tail = nextTail
        return output
    }

    private enum RenderError: Error { case invalidFormat }
}
