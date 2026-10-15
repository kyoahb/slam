import AVFoundation
import AudioToolbox

/// Short sounds made by tools/sounds.py. Set and record are quiet, mix with music and follow the silent switch;
/// rest over is loud, turns music down while it plays and sounds even on silent.
@MainActor
enum Sounds {
    enum Name: String {
        case set, record, rest
    }

    private static var players: [Name: AVAudioPlayer] = [:]

    static func play(_ name: Name) {
        let session = AVAudioSession.sharedInstance()
        if name == .rest {
            try? session.setCategory(.playback, options: [.duckOthers])
        } else {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        if players[name] == nil, let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav") {
            players[name] = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
        guard name == .rest else { return }
        // Music comes back up once it is done.
        Task {
            try? await Task.sleep(for: .seconds(player.duration + 0.1))
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Two full vibrations: felt in a pocket or with the phone face down on a bench.
    static func buzz() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
