import Foundation
import WatchConnectivity
import SlamCore

/// The Slam app on the Apple Watch: it gets what the phone shows (the rest, the set to do, its setup, the sets
/// after) and sends back Done, ±15 s and Skip.
final class WristLink: NSObject, WCSessionDelegate {
    private weak var model: AppModel?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    @MainActor
    func start(_ model: AppModel) {
        self.model = model
        session?.delegate = self
        session?.activate()
    }

    /// The latest state, kept for when the watch app opens, and sent straight away when it is open.
    func send(_ state: WristState?) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let message: [String: Any] = state.flatMap { $0.encoded() }.map { [WristState.Key.state: $0] }
            ?? [WristState.Key.none: Date().timeIntervalSinceReferenceDate]
        try? session.updateApplicationContext(message)
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: nil) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.model?.refreshWrist() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A different watch was paired: talk to that one.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.model?.watchPressed(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.model?.watchPressed(userInfo) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.model?.refreshWrist() }
    }
}

extension AppModel {
    /// What the watch shows: the rest, then the sets not yet ticked, the next one first.
    func wristState() -> WristState? {
        guard let editor else { return nil }
        var lines: [WristState.Line] = []
        for e in editor.workout.exercises where lines.count < 5 {
            guard let ex = byId[e.exerciseId] else { continue }
            let holders = editor.placeholders(e)
            let labels = Previous.labels(e.sets)
            let settings = ex.settings.compactMap { c -> String? in
                let v = e[setting: c.id]
                return v.isEmpty ? nil : c.name + " " + v
            }.joined(separator: " · ")
            for (i, set) in e.sets.enumerated() where !set.done && lines.count < 5 {
                let s = set.filled(from: holders[i])
                let label = switch s.kind {
                case .warmup: "Warm-up"
                case .drop: "Drop set"
                case .normal: "Set " + labels[i]
                }
                lines.append(WristState.Line(entry: e.id, set: set.id, exercise: ex.name, label: label,
                                             values: SetText.describe(s, ex), setup: s.load?.summary(ex.rig), settings: settings))
            }
        }
        return WristState(title: editor.workout.title, start: editor.workout.start, restEnd: restEnd, restLength: restLength,
                          sets: lines)
    }

    func refreshWrist() {
        guard !demo else { return }
        wristDelay?.cancel()
        wrist.send(wristState())
    }

    /// After typing: once it stops for a moment.
    func refreshWristSoon() {
        guard !demo else { return }
        wristDelay?.cancel()
        wristDelay = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refreshWrist()
        }
    }

    /// A press on the watch. One that took long to arrive is dropped when the phone has moved on.
    func watchPressed(_ message: [String: Any]) {
        guard let editor, let raw = message[WristState.Key.action] as? String, let action = WristState.Action(rawValue: raw) else { return }
        let sameRest = (message[WristState.Key.rest] as? Double).map { abs($0 - (restEnd?.timeIntervalSinceReferenceDate ?? 0)) < 1 } ?? false
        switch action {
        case .done:
            guard let entry = (message[WristState.Key.entry] as? String).flatMap(UUID.init(uuidString:)),
                  let set = (message[WristState.Key.set] as? String).flatMap(UUID.init(uuidString:)),
                  editor.entry(entry)?.sets.first(where: { $0.id == set })?.done == false else { return }
            editor.toggleDone(entry, set)
        case .adjust:
            if sameRest, let by = message[WristState.Key.by] as? Int { adjustRest(by) }
        case .skip:
            if sameRest { skipRest() }
        }
        refreshWrist()
    }
}
