import Foundation
import HevyImport
import SlamServer

let usage = """
    slam serve                          run the sync server (see Server.run for its environment)
    slam import-hevy <raw-dir> <out>    turn pulled Hevy pages into a Slam library plus a dry-run report
    """

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "serve":
        try await Server.run(ProcessInfo.processInfo.environment)
    case "import-hevy" where args.count == 3:
        try HevyImport.run(raw: URL(fileURLWithPath: args[1], isDirectory: true),
                           out: URL(fileURLWithPath: args[2], isDirectory: true))
    default:
        print(usage)
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("slam: \(error)\n".utf8))
    exit(1)
}
