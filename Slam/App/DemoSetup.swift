import SwiftUI
import SlamCore

/// Screenshot mode (`-demo -screen name`, `-fresh` for an empty install): made-up history, two photos, then the named screen.
extension AppModel {
    func prepareDemo(_ args: [String]) {
        addDemoPhotos()
        let screen = args.firstIndex(of: "-screen").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "workout"
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent("demo-ready")
        try? FileManager.default.removeItem(at: ready)
        // After launch: selecting a cell talks to UIApplication, which does not exist yet.
        Task { @MainActor in
            await self.show(screen)
            // CI takes the screenshot once this file exists: the screen and its animations have settled.
            try? await Task.sleep(for: .seconds(2))
            FileManager.default.createFile(atPath: ready.path, contents: nil)
        }
    }

    private func show(_ screen: String) async {
        switch screen {
        case "routines":
            tab = .workout
        case "workout":
            showWorkout = true
        case "weight", "reps", "pin":
            showWorkout = true
            if let editor, let entry = editor.workout.exercises.first, entry.sets.count > 2 {
                editor.select(Cell(entry: entry.id, set: entry.sets[2].id, field: screen == "reps" ? .reps : .kg))
                if screen == "pin" {
                    editor.pinPlates = true
                    editor.addPlate(5)
                }
            }
        case "plates", "dumbbell", "tbar":
            showWorkout = true
            // Set 2 of the bench (one more plate than last time), of the lateral raise with two clip-ons, or of the T-bar row.
            let name = ["plates": "Bench Press (Barbell)", "dumbbell": "Lateral Raise (Dumbbell)"][screen] ?? "Precor T Bar Row - Row"
            if let editor, let entry = editor.workout.exercises.first(where: { byId[$0.exerciseId]?.name == name }),
               entry.sets.count > 1 {
                editor.select(Cell(entry: entry.id, set: entry.sets[1].id, field: .kg))
                if screen == "plates" {
                    editor.addPlate(2.5)
                } else if screen == "dumbbell" {
                    editor.clearPlates()
                    editor.toggleClip(0.5)
                    editor.toggleClip(1)
                } else {
                    editor.addPlate(5)
                }
            }
        case "record":
            showWorkout = true
            // Tick set 3 of the first exercise heavier than ever: the record banner drops in.
            if let editor, let entry = editor.workout.exercises.first, entry.sets.count > 2,
               let top = byId[entry.exerciseId]?.stack.last {
                let kg = Cell(entry: entry.id, set: entry.sets[2].id, field: .kg)
                editor.select(kg)
                editor.pickSlot(top)
                if (editor.load(kg)?.addOn ?? 0) == 0 { editor.toggleAddOn() }
                editor.select(Cell(entry: entry.id, set: entry.sets[2].id, field: .reps))
                editor.key(.digit(1))
                editor.key(.digit(2))
                editor.select(nil)
                editor.toggleDone(entry.id, entry.sets[2].id)
                skipRest()
            }
        case "form", "form-bar":
            showWorkout = true
            // A sheet set while the workout is still sliding up is dropped.
            try? await Task.sleep(for: .seconds(0.8))
            let name = screen == "form" ? "Precor Leg Extension" : "Bench Press (Barbell)"
            if let id = exercises.first(where: { $0.name == name })?.id {
                editor?.editingExercise = ExerciseLink(id: id)
            }
        case "rest":
            showWorkout = true
            restLength = settings.restSeconds
            restEnd = Date().addingTimeInterval(87)
        case "live":
            restLength = settings.restSeconds
            restEnd = Date().addingTimeInterval(87)
            demoLive = true
        case "watch":
            // The last workout with the elliptical, linked to its Watch workout; done first so it shows at the top.
            tab = .history
            let cardio = { (e: WorkoutExercise) in self.byId[e.exerciseId]?.watchActivities.isEmpty == false }
            if var w = workouts.first(where: { $0.exercises.contains(where: cardio) }),
               let i = w.exercises.firstIndex(where: cardio) {
                let end = w.start.addingTimeInterval(33 * 60)
                let link = WatchLink(id: UUID(), start: end.addingTimeInterval(-1930), end: end,
                                     meters: 6200, kcal: 412, heartRate: 141)
                w.exercises[i].watch = link
                if !w.exercises[i].sets.isEmpty {
                    w.exercises[i].sets[0].seconds = link.seconds
                    w.exercises[i].sets[0].meters = link.meters
                }
                w.exercises.move(fromOffsets: [i], toOffset: 0)
                insert(w)
                historyPath.append(WorkoutLink(id: w.id))
            }
        case "save":
            showWorkout = true
            editor?.saving = true
        case "history-sheet":
            showWorkout = true
            try? await Task.sleep(for: .seconds(0.8))
            if let id = editor?.workout.exercises.first?.exerciseId { editor?.historyFor = ExerciseLink(id: id) }
        case "picker":
            showWorkout = true
            try? await Task.sleep(for: .seconds(0.8))
            editor?.picking = true
        case "routine":
            tab = .workout
            editRoutine(routines.first)
        case "history":
            tab = .history
        case "detail":
            tab = .history
            if let w = workouts.first { historyPath.append(WorkoutLink(id: w.id)) }
        case "profile":
            tab = .profile
        case "stats", "exercises", "calendar", "photos", "settings":
            tab = .profile
            let routes: [String: ProfileRoute] = ["stats": .statistics, "exercises": .exercises, "calendar": .calendar,
                                                  "photos": .photos, "settings": .settings]
            if let r = routes[screen] { profilePath.append(r) }
        case "volume":
            tab = .profile
            profilePath.append(ProfileRoute.statistics)
            profilePath.append(StatsRoute.volume)
        case "exercise":
            tab = .profile
            if let e = exercises.first(where: { $0.name == "Precor Leg Extension" }) ?? exercises.first {
                profilePath.append(ExerciseLink(id: e.id))
            }
        default:
            break
        }
    }

    private func addDemoPhotos() {
        for (i, hue) in [0.58, 0.08].enumerated() where workouts.indices.contains(i) {
            guard let data = Self.demoImage(hue: hue), var p = addPhoto(data) else { continue }
            var w = workouts[i]
            p.addedAt = w.start.addingTimeInterval(45 * 60)
            w.photos.append(p)
            insert(w)
        }
    }

    private static func demoImage(hue: Double) -> Data? {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.45, brightness: 0.42, alpha: 1).cgColor,
                          UIColor(hue: hue + 0.08, saturation: 0.55, brightness: 0.12, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.10).setFill()
            UIBezierPath(ovalIn: CGRect(x: 150, y: 260, width: 600, height: 600)).fill()
            UIColor.white.withAlphaComponent(0.16).setFill()
            UIBezierPath(roundedRect: CGRect(x: 120, y: 940, width: 660, height: 70), cornerRadius: 35).fill()
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
