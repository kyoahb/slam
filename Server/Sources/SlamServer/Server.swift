import Foundation
import Hummingbird
import SlamCore

public enum Server {
    /// Runs the server from its environment: `SLAM_DATA`, `SLAM_BACKUPS`, `SLAM_PORT` and the three tokens.
    public static func run(_ env: [String: String]) async throws {
        func token(_ name: String) throws -> String {
            guard let v = env[name], v.count >= 32 else { throw ServerError.missing(name) }
            return v
        }
        let tokens = try Tokens(phone: token("SLAM_PHONE_TOKEN"), read: token("SLAM_READ_TOKEN"),
                                write: token("SLAM_WRITE_TOKEN"))
        // Without it every answer with a date in it crashes the server.
        guard TimeZone(identifier: "Europe/London") != nil else { throw ServerError.noTimeZones }
        let vault = try Vault(root: URL(fileURLWithPath: env["SLAM_DATA"] ?? "/data", isDirectory: true))
        let port = Int(env["SLAM_PORT"] ?? "") ?? 9097
        if let dir = env["SLAM_BACKUPS"] {
            Task { await backups(vault, to: URL(fileURLWithPath: dir, isDirectory: true)) }
        }
        let app = Application(router: Routes.router(vault, tokens),
                              configuration: .init(address: .hostname("0.0.0.0", port: port), serverName: "slam"))
        try await app.runService()
    }

    /// A copy a day: checked every hour, made when the newest one is a day old.
    static func backups(_ vault: Vault, to dir: URL) async {
        while !Task.isCancelled {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let newest = names.filter { $0.hasPrefix("slam-") }.compactMap { name in
                (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.creationDate] as? Date
                    ?? (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.modificationDate] as? Date
            }.max()
            if newest.map({ Date().timeIntervalSince($0) > 23 * 3600 }) ?? true {
                do {
                    let dest = try await vault.backup(to: dir)
                    print("backup: \(dest.lastPathComponent)")
                } catch {
                    print("backup failed: \(error)")
                }
            }
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}

public enum ServerError: Error, CustomStringConvertible {
    case missing(String)
    case noTimeZones

    public var description: String {
        switch self {
        case let .missing(name): "\(name) must be set (32 characters or more)"
        case .noTimeZones: "no time zone data (install tzdata)"
        }
    }
}
