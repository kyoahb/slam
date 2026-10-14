import Foundation
import SlamCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Turns a Hevy pull into a Slam library, as a dry run: everything goes to one folder and nowhere else.
public enum HevyImport {
    /// Reads the Hevy pages in `raw` and writes to `out`: the library in Slam's file format under `library/`,
    /// `dry-run.html`, `summary.json`, `import-map.json` and `note-lines.json`. The person's rules come from
    /// `out/rules.json` when it exists. Run again on the same `out`, every id is kept.
    public static func run(raw: URL, out: URL) throws {
        let mask = umask(0o077)
        defer { umask(mask) }
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let rulesURL = out.appendingPathComponent("rules.json")
        let rules = try Rules.load(rulesURL)
        print(rules == nil ? "No rules at \(rulesURL.path): plain English only, no gyms." : "Rules: \(rulesURL.path)")
        let hevy = try Hevy.load(raw)

        let libURL = out.appendingPathComponent("library", isDirectory: true)
        let mapURL = out.appendingPathComponent("import-map.json")
        let previous = fm.fileExists(atPath: libURL.appendingPathComponent("exercises.json").path)
            ? try FileStore(root: libURL).load() : nil
        let previousMap = (try? Data(contentsOf: mapURL)).flatMap { try? JSONDecoder().decode(ImportMap.self, from: $0) }
            ?? ImportMap()

        let im = Importer(hevy: hevy, rules: rules ?? Rules(), previous: previous, previousMap: previousMap)
        try im.run()

        let store = FileStore(root: libURL)
        try store.save(im.library)
        if let previous {
            let kept = Set(im.library.workouts.map(\.id))
            for w in previous.workouts where !kept.contains(w.id) { try store.delete(workout: w.id) }
        }
        let report = Report(im: im, rulesPath: rules == nil ? "none" : rulesURL.path)
        let summary = report.summary()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(im.map).write(to: mapURL, options: .atomic)
        try enc.encode(summary).write(to: out.appendingPathComponent("summary.json"), options: .atomic)
        try enc.encode(im.tally.audit).write(to: out.appendingPathComponent("note-lines.json"), options: .atomic)
        try Data(report.html().utf8).write(to: out.appendingPathComponent("dry-run.html"), options: .atomic)
        try lockDown(out)

        let c = summary.counts
        print("\(c.workouts) workouts, \(c.routines) routines, \(c.exercises) exercises, \(c.sets) sets, "
              + "\(c.setsWithBreakdown) with a full breakdown, \(c.misses) misses.")
        print("Report: \(out.appendingPathComponent("dry-run.html").path)")
    }

    /// Only the owner can read what was written: folders 700, files 600.
    static func lockDown(_ dir: URL) throws {
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let items = fm.enumerator(atPath: dir.path)
        while let rel = items?.nextObject() as? String {
            let path = dir.appendingPathComponent(rel).path
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &isDir)
            try fm.setAttributes([.posixPermissions: isDir.boolValue ? 0o700 : 0o600], ofItemAtPath: path)
        }
    }
}
