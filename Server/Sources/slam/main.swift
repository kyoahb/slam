import Foundation
import HevyImport
import SlamCore
import SlamServer

let usage = """
    slam serve                          run the sync server (see Server.run for its environment)
    slam import-hevy <raw-dir> <out>    turn pulled Hevy pages into a Slam library plus a dry-run report
    slam replace <library-dir>          make the server's data (SLAM_DATA) exactly that library; run with the
                                        server stopped; refuses to drop a workout the library lacks
    """

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "serve":
        try await Server.run(ProcessInfo.processInfo.environment)
    case "import-hevy" where args.count == 3:
        try HevyImport.run(raw: URL(fileURLWithPath: args[1], isDirectory: true),
                           out: URL(fileURLWithPath: args[2], isDirectory: true))
    case "replace" where args.count == 2:
        let dir = URL(fileURLWithPath: args[1], isDirectory: true)
        let lib = try FileStore(root: dir).load()
        // The store skips a workout it cannot read; here that would lose it.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("workouts").path)
            .filter { $0.hasSuffix(".json") }.count
        guard files == lib.workouts.count else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "\(files - lib.workouts.count) workouts cannot be read"])
        }
        let vault = try Vault(root: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SLAM_DATA"] ?? "/data", isDirectory: true))
        let (written, deleted) = try await vault.replace(with: lib)
        let now = await vault.library()
        print("\(written) records written, \(deleted) deleted. The server now has \(now.workouts.count) workouts, "
            + "\(now.exercises.count) exercises, \(now.routines.count) routines, \(now.folders.count) folders, \(now.gyms.count) gyms.")
    default:
        print(usage)
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("slam: \(error)\n".utf8))
    exit(1)
}
