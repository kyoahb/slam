import AVFoundation
import AudioToolbox

/// Short, quiet sounds made by tools/sounds.py. They mix with music and follow the silent switch.
@MainActor
enum Sounds {
    enum Name: String {
        case set, record, rest
    }

    private static var players: [Name: AVAudioPlayer] = [:]
    private static var ready = false

    static func play(_ name: Name) {
        if !ready {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            ready = true
        }
        if players[name] == nil, let url = Bundle.main.url(forResource: name.rawValue, withExtension: "wav") {
            players[name] = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }

    /// A full vibration: felt even with the phone face down on a bench.
    static func buzz() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
