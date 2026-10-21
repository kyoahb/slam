import AVFoundation
import AudioToolbox

/// Short sounds made by tools/sounds.py, played through one audio engine that mixes with music and sounds on silent.
/// While a rest runs the engine stays on, so iOS keeps Slam running in a pocket or locked, and the rest ding is
/// queued in the engine for the exact end. Between rests it is off.
@MainActor
enum Sounds {
    enum Name: String {
        case set, record, rest
    }

    private static let engine = AVAudioEngine()
    /// Set and record: played straight away.
    private static let now = AVAudioPlayerNode()
    /// Rest over: queued for the end of the rest.
    private static let later = AVAudioPlayerNode()
    private static var wired = false
    private static var buffers: [Name: AVAudioPCMBuffer] = [:]
    private static var restEnd: Date?
    private static var nowUntil = Date.distantPast
    private static var stopper: Task<Void, Never>?

    /// The rest ding is queued and will play by itself.
    static var restQueued: Bool { restEnd != nil && engine.isRunning }

    static func play(_ name: Name) {
        guard let buffer = buffer(name), start() else { return }
        now.scheduleBuffer(buffer, at: nil, options: .interrupts)
        now.play()
        nowUntil = Date().addingTimeInterval(length(buffer))
        stopLater()
    }

    /// Queues the rest ding for `end`, in place of any queued before.
    static func queueRest(at end: Date) {
        guard let buffer = buffer(.rest), start() else {
            restEnd = nil
            return
        }
        restEnd = end
        later.stop()
        let wait = max(0, end.timeIntervalSinceNow)
        later.scheduleBuffer(buffer, at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: wait)))
        later.play()
        stopLater()
    }

    static func cancelRest() {
        guard wired else { return }
        restEnd = nil
        later.stop()
        stopLater()
    }

    /// One full vibration: felt in a pocket or with the phone face down on a bench.
    static func buzz() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    // MARK: Engine

    /// The engine on; false when iOS will not let it start (during a phone call).
    private static func start() -> Bool {
        if engine.isRunning { return true }
        guard let format = buffer(.rest)?.format else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            if !wired {
                engine.attach(now)
                engine.attach(later)
                engine.connect(now, to: engine.mainMixerNode, format: format)
                engine.connect(later, to: engine.mainMixerNode, format: format)
                watch()
                wired = true
            }
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// Off once nothing is playing or queued, so Slam sleeps between rests.
    private static func stopLater() {
        stopper?.cancel()
        let restUntil = restEnd.map { $0.addingTimeInterval(buffers[.rest].map(length) ?? 0) } ?? .distantPast
        let at = max(nowUntil, restUntil)
        stopper = Task {
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow) + 0.3))
            guard !Task.isCancelled else { return }
            restEnd = nil
            now.stop()
            later.stop()
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// A phone call or Siri, or headphones coming or going, stop the engine: start it again and requeue the rest.
    private static func watch() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended else { return }
            MainActor.assumeIsolated { requeue() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { requeue() }
        }
    }

    private static func requeue() {
        guard let end = restEnd, end > Date() else { return }
        queueRest(at: end)
    }

    private static func buffer(_ name: Name) -> AVAudioPCMBuffer? {
        if let b = buffers[name] { return b }
        guard let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: b)) != nil else { return nil }
        buffers[name] = b
        return b
    }

    private static func length(_ b: AVAudioPCMBuffer) -> TimeInterval {
        Double(b.frameLength) / b.format.sampleRate
    }
}
