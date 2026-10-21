import Foundation
import WatchConnectivity
import UserNotifications
import WatchKit
import SlamCore

/// What the phone shows, mirrored. The countdown runs here from the rest's end, the wrist gets one tap when it
/// ends, and presses go back to the phone, which only takes them if they still fit what it shows.
@Observable @MainActor
final class WristModel {
    var state: WristState?
    /// When the phone last said something, so an older message arriving late is ignored.
    private var heard = Date.distantPast
    @ObservationIgnored private let link = PhoneLink()
    let demo: Bool

    init(demo: Bool) {
        self.demo = demo
        if demo {
            state = .sample
            return
        }
        UNUserNotificationCenter.current().delegate = WristAlerts.shared
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        link.start(self)
    }

    /// Woken in the background by something from the phone, so a rest started with the wrist down still taps:
    /// stays up until it has arrived.
    func catchUp() async {
        let until = Date().addingTimeInterval(10)
        while Date() < until, WCSession.default.activationState != .activated || WCSession.default.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func received(_ message: [String: Any]) {
        if let data = message[WristState.Key.state] as? Data, let s = WristState.decoded(data) {
            guard s.sent >= heard else { return }
            heard = s.sent
            show(s)
        } else if let t = message[WristState.Key.none] as? Double {
            let at = Date(timeIntervalSinceReferenceDate: t)
            guard at >= heard else { return }
            heard = at
            show(nil)
        }
    }

    private func show(_ s: WristState?) {
        let before = state?.restEnd
        state = s
        if s?.restEnd != before { scheduleTap() }
    }

    func done(_ line: WristState.Line) {
        WKInterfaceDevice.current().play(.success)
        state?.sets.removeAll { $0.set == line.set }
        link.send([WristState.Key.action: WristState.Action.done.rawValue,
                   WristState.Key.entry: line.entry.uuidString, WristState.Key.set: line.set.uuidString])
    }

    func adjust(_ by: Int) {
        guard let end = state?.restEnd else { return }
        link.send([WristState.Key.action: WristState.Action.adjust.rawValue, WristState.Key.by: by,
                   WristState.Key.rest: end.timeIntervalSinceReferenceDate])
        let next = end.addingTimeInterval(TimeInterval(by))
        if next <= Date() {
            state?.restEnd = nil
        } else {
            state?.restEnd = next
            state?.restLength = max(1, (state?.restLength ?? 0) + by)
        }
        scheduleTap()
    }

    func skip() {
        guard let end = state?.restEnd else { return }
        link.send([WristState.Key.action: WristState.Action.skip.rawValue, WristState.Key.rest: end.timeIntervalSinceReferenceDate])
        state?.restEnd = nil
        scheduleTap()
    }

    /// One tap when the rest ends, with the app in front or not. It has the phone's id, so the watch shows
    /// one notice, not the phone's as well.
    private func scheduleTap() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard !demo, let end = state?.restEnd, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        if let next = state?.sets.first { content.body = next.exercise + " · " + next.label }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }
}

final class PhoneLink: NSObject, WCSessionDelegate {
    private weak var model: WristModel?

    @MainActor
    func start(_ model: WristModel) {
        self.model = model
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Straight away when the phone answers, else queued until it does.
    func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
        } else {
            session.transferUserInfo(message)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.model?.received(context) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.model?.received(context) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.model?.received(message) }
    }
}

final class WristAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WristAlerts()

    /// In the app as well: the tap is the point.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension WristState {
    /// For screenshots: made-up sets mid-rest.
    static var sample: WristState {
        let press = UUID(), raise = UUID()
        return WristState(title: "Push Day", start: Date().addingTimeInterval(-1_520), restEnd: Date().addingTimeInterval(64),
                          restLength: 90, sets: [
                              Line(entry: press, set: UUID(), exercise: "Chest Press (Machine)", label: "Set 3",
                                   values: "60 kg × 8", setup: "55 +5", settings: "Seat 4 · Handles 2"),
                              Line(entry: press, set: UUID(), exercise: "Chest Press (Machine)", label: "Drop set",
                                   values: "45 kg × 10", setup: "45", settings: "Seat 4 · Handles 2"),
                              Line(entry: raise, set: UUID(), exercise: "Lateral Raise (Dumbbell)", label: "Set 1",
                                   values: "10 kg × 12", setup: nil, settings: ""),
                              Line(entry: raise, set: UUID(), exercise: "Lateral Raise (Dumbbell)", label: "Set 2",
                                   values: "10 kg × 12", setup: nil, settings: ""),
                          ])
    }
}
