import SwiftUI
import SlamCore
import UserNotifications

enum AppTab: Hashable {
    case history, workout, profile
}

struct WorkoutLink: Hashable { let id: UUID }
struct ExerciseLink: Hashable { let id: UUID }
struct WeekLink: Hashable { let start: Date }
enum ProfileRoute: Hashable { case statistics, exercises, calendar, photos, settings }

@Observable @MainActor
final class AppModel {
    var exercises: [Exercise] = []
    var folders: [Folder] = []
    var routines: [Routine] = []
    var gyms: [Gym] = []
    var settings = SlamCore.Settings()
    var workouts: [Workout] = []
    private(set) var byId: [UUID: Exercise] = [:]
    private(set) var records: [UUID: [Record]] = [:]

    var editor: WorkoutEditor?
    var showWorkout = false
    var routineEditor: WorkoutEditor?
    var tab: AppTab = .workout
    var historyPath = NavigationPath()
    var profilePath = NavigationPath()

    var restEnd: Date?
    var restLength = 0
    /// Screenshot mode: the lock screen and Dynamic Island drawn over the app.
    var demoLive = false
    var stopwatchStart: Date?
    var stopwatchBanked: TimeInterval = 0

    let store: FileStore
    let demo: Bool
    private let thumbs = NSCache<NSString, UIImage>()

    /// The Slam server this phone syncs with, if it was set up.
    var syncConfig: SyncConfig?
    var syncStatus = SyncStatus()
    @ObservationIgnored var syncDelay: Task<Void, Never>?

    init(store: FileStore, library: Library, demo: Bool) {
        self.store = store
        self.demo = demo
        syncConfig = demo ? nil : SyncConfig.load()
        syncStatus.last = demo ? nil : store.loadSync().lastSync
        exercises = library.exercises
        folders = library.folders
        routines = library.routines
        gyms = library.gyms
        settings = library.settings
        workouts = library.workouts
        reindex()
        recomputeRecords()
        if let active = library.active {
            editor = WorkoutEditor(workout: active, mode: .live, app: self)
        }
    }

    static func launch() -> AppModel {
        let args = ProcessInfo.processInfo.arguments
        let demo = args.contains("-demo")
        let root: URL
        if demo {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("slam-demo", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
        } else {
            root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let store = FileStore(root: root)
        var library = (try? store.load()) ?? Library()
        if demo {
            // -fresh: a new install with nothing logged, to see the empty screens.
            library = args.contains("-fresh") ? Library() : Demo.library()
            try? store.save(library)
        } else {
            // Once: the starter exercises earlier builds added, unless used or changed.
            let marker = root.appendingPathComponent("starter-removed")
            if !FileManager.default.fileExists(atPath: marker.path) {
                if library.removeUnusedStarter() > 0 { try? store.saveExercises(library.exercises) }
                FileManager.default.createFile(atPath: marker.path, contents: nil)
            }
        }
        let model = AppModel(store: store, library: library, demo: demo)
        if demo { model.prepareDemo(args) }
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        model.refreshLiveActivity()
        return model
    }

    // MARK: Lookups

    func reindex() {
        byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func recomputeRecords() {
        records = Records.all(workouts, exercises: byId)
    }

    func routine(_ id: UUID?) -> Routine? {
        guard let id else { return nil }
        return routines.first { $0.id == id }
    }

    func gym(_ id: UUID?) -> Gym? {
        guard let id else { return nil }
        return gyms.first { $0.id == id }
    }

    func workout(_ id: UUID) -> Workout? { workouts.first { $0.id == id } }

    func lastTime(_ exerciseId: UUID, excluding: UUID?, before: Date?) -> WorkoutExercise? {
        Previous.last(exerciseId, in: workouts, excluding: excluding, before: before)
    }

    /// The routine's long-term note for an exercise; for empty workouts, the note from any routine that has one.
    func longNote(_ exerciseId: UUID, routineId: UUID?) -> String {
        if let note = routine(routineId)?.exercises.first(where: { $0.exerciseId == exerciseId })?.note, !note.isEmpty {
            return note
        }
        for r in routines {
            if let note = r.exercises.first(where: { $0.exerciseId == exerciseId && !$0.note.isEmpty })?.note { return note }
        }
        return ""
    }

    var recentExerciseIds: [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for w in workouts {
            for e in w.exercises where !seen.contains(e.exerciseId) {
                seen.insert(e.exerciseId)
                out.append(e.exerciseId)
            }
            if out.count >= 20 { break }
        }
        return out
    }

    func uses(_ exerciseId: UUID) -> Int {
        workouts.filter { $0.exercises.contains { $0.exerciseId == exerciseId } }.count
            + routines.filter { $0.exercises.contains { $0.exerciseId == exerciseId } }.count
    }

    // MARK: Workouts

    func startEmpty() {
        begin(Workout(title: Self.defaultTitle(Date()), gymId: settings.gymId))
    }

    func start(_ routine: Routine) {
        begin(Workout.from(routine, exercises: byId, history: workouts, gymId: settings.gymId))
    }

    private func begin(_ w: Workout) {
        skipRest()
        editor = WorkoutEditor(workout: w, mode: .live, app: self)
        saveActive(w)
        showWorkout = true
        refreshLiveActivity()
        checkWatch()
        if !demo {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }
    }

    func saveActive(_ w: Workout?) {
        try? store.saveActive(w)
        syncSoon()
    }

    func discardActive() {
        editor = nil
        showWorkout = false
        skipRest()
        saveActive(nil)
    }

    func finishActive(updateRoutine: Bool) {
        guard let editor else { return }
        var w = editor.cleaned()
        w.end = Date()
        if updateRoutine, let r = routine(w.routineId) { save(routine: RoutineDiff.apply(w, to: r, byId)) }
        insert(w)
        self.editor = nil
        showWorkout = false
        skipRest()
        saveActive(nil)
        historyPath = NavigationPath()
        tab = .history
    }

    func insert(_ w: Workout) {
        workouts.removeAll { $0.id == w.id }
        workouts.append(w)
        workouts.sort { $0.start > $1.start }
        try? store.save(workout: w)
        recomputeRecords()
        syncSoon()
    }

    func delete(_ w: Workout) {
        workouts.removeAll { $0.id == w.id }
        try? store.delete(workout: w.id)
        for p in w.photos { try? FileManager.default.removeItem(at: store.photosDir.appendingPathComponent(p.file)) }
        recomputeRecords()
        syncSoon()
    }

    static func defaultTitle(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning Workout"
        case 12..<17: return "Afternoon Workout"
        case 17..<22: return "Evening Workout"
        default: return "Night Workout"
        }
    }

    // MARK: Rest timer

    func startRest(_ seconds: Int) {
        restLength = seconds
        restEnd = Date().addingTimeInterval(TimeInterval(seconds))
        scheduleRestAlert()
        refreshLiveActivity()
    }

    func adjustRest(_ delta: Int) {
        guard let end = restEnd else { return }
        let next = end.addingTimeInterval(TimeInterval(delta))
        if next <= Date() {
            skipRest()
            return
        }
        restEnd = next
        restLength = max(1, restLength + delta)
        scheduleRestAlert()
        refreshLiveActivity()
    }

    func skipRest() {
        restEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        refreshLiveActivity()
    }

    /// Chime and buzz, unless the app was away when it ended (the notification already told you).
    func restFinished(late: Bool) {
        restEnd = nil
        refreshLiveActivity()
        guard !late, !demo else { return }
        Sounds.play(.rest)
        Sounds.buzz()
    }

    private func scheduleRestAlert() {
        guard let end = restEnd, !demo else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("rest.wav"))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }

    // MARK: Routines and folders

    func save(routine r: Routine) {
        if let i = routines.firstIndex(where: { $0.id == r.id }) {
            routines[i] = r
        } else {
            routines.append(r)
        }
        persistRoutines()
    }

    func delete(routine r: Routine) {
        routines.removeAll { $0.id == r.id }
        persistRoutines()
    }

    func duplicate(_ r: Routine) {
        var copy = r
        copy.id = UUID()
        copy.name = r.name + " copy"
        copy.hevyId = nil
        save(routine: copy)
    }

    func move(_ r: Routine, to folder: UUID?) {
        var moved = r
        moved.folderId = folder
        save(routine: moved)
    }

    func addFolder(_ name: String) {
        folders.append(Folder(name: name))
        persistRoutines()
    }

    func rename(folder: Folder, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].name = name
        persistRoutines()
    }

    func delete(folder: Folder) {
        folders.removeAll { $0.id == folder.id }
        for i in routines.indices where routines[i].folderId == folder.id { routines[i].folderId = nil }
        persistRoutines()
    }

    func persistRoutines() {
        try? store.saveRoutines(folders, routines)
        syncSoon()
    }

    func editRoutine(_ r: Routine?, folder: UUID? = nil) {
        let id = r?.id ?? UUID()
        let w = Workout(id: id, title: r?.name ?? "", routineId: id, exercises: r?.exercises ?? [])
        let ed = WorkoutEditor(workout: w, mode: .routine, app: self)
        ed.folderId = r?.folderId ?? folder
        ed.isNew = r == nil
        routineEditor = ed
    }

    func saveRoutine(from ed: WorkoutEditor) {
        let w = ed.workout
        var r = routine(w.id) ?? Routine(id: w.id, name: "")
        r.name = w.title.trimmingCharacters(in: .whitespaces).isEmpty ? "New Routine" : w.title
        r.exercises = w.exercises
        r.folderId = ed.folderId
        save(routine: r)
        routineEditor = nil
    }

    // MARK: Exercises, gyms, settings

    func save(exercise e: Exercise) {
        if let i = exercises.firstIndex(where: { $0.id == e.id }) {
            exercises[i] = e
        } else {
            exercises.append(e)
        }
        reindex()
        try? store.saveExercises(exercises)
        syncSoon()
    }

    func delete(exercise e: Exercise) {
        guard uses(e.id) == 0 else { return }
        exercises.removeAll { $0.id == e.id }
        reindex()
        try? store.saveExercises(exercises)
        syncSoon()
    }

    @discardableResult
    func addGym(_ name: String) -> Gym {
        let g = Gym(name: name)
        gyms.append(g)
        try? store.saveGyms(gyms)
        syncSoon()
        if settings.gymId == nil {
            settings.gymId = g.id
            saveSettings()
        }
        return g
    }

    func rename(gym: Gym, to name: String) {
        guard let i = gyms.firstIndex(where: { $0.id == gym.id }) else { return }
        gyms[i].name = name
        try? store.saveGyms(gyms)
        syncSoon()
    }

    func delete(gym: Gym) {
        gyms.removeAll { $0.id == gym.id }
        try? store.saveGyms(gyms)
        syncSoon()
        if settings.gymId == gym.id {
            settings.gymId = gyms.first?.id
            saveSettings()
        }
    }

    func saveSettings() {
        try? store.saveSettings(settings)
        syncSoon()
    }

    // MARK: Photos

    func addPhoto(_ data: Data) -> Photo? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = image.scaledDown(to: 2048)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: store.photosDir, withIntermediateDirectories: true)
            try jpeg.write(to: store.photosDir.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        return Photo(file: name)
    }

    func image(_ file: String) -> UIImage? {
        UIImage(contentsOfFile: store.photosDir.appendingPathComponent(file).path)
    }

    func thumbnail(_ file: String) -> UIImage? {
        if let hit = thumbs.object(forKey: file as NSString) { return hit }
        guard let full = image(file) else { return nil }
        let thumb = full.preparingThumbnail(of: full.size.fitting(720)) ?? full
        thumbs.setObject(thumb, forKey: file as NSString)
        return thumb
    }

    func exportFile() -> URL? {
        let lib = Library(exercises: exercises, folders: folders, routines: routines, gyms: gyms, settings: settings,
                          workouts: workouts)
        guard let data = try? store.export(lib) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("slam-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // In the app the rest timer chimes and buzzes itself.
        []
    }
}

extension CGSize {
    func fitting(_ longest: CGFloat) -> CGSize {
        let scale = min(1, longest / max(width, height, 1))
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }
}

extension UIImage {
    func scaledDown(to longest: CGFloat) -> UIImage {
        let target = size.fitting(longest)
        guard target != size else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
