import SwiftUI
import SlamCore

/// Screenshot mode (`-demo -screen name`, `-fresh` for an empty install): made-up history, two photos, then the named screen.
extension AppModel {
    func prepareDemo(_ args: [String]) {
        addDemoPhotos()
        let screen = args.firstIndex(of: "-screen").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "workout"
        // After launch: selecting a cell talks to UIApplication, which does not exist yet.
        Task { @MainActor in self.show(screen) }
    }

    private func show(_ screen: String) {
        switch screen {
        case "routines":
            tab = .workout
        case "workout":
            showWorkout = true
        case "weight", "reps":
            showWorkout = true
            if let editor, let entry = editor.workout.exercises.first, entry.sets.count > 2 {
                editor.select(Cell(entry: entry.id, set: entry.sets[2].id, field: screen == "weight" ? .kg : .reps))
            }
        case "record":
            showWorkout = true
            // Tick set 3 of the first exercise heavier than ever: the record banner drops in.
            if let editor, let entry = editor.workout.exercises.first, entry.sets.count > 2,
               let top = byId[entry.exerciseId]?.stack.last {
                let kg = Cell(entry: entry.id, set: entry.sets[2].id, field: .kg)
                editor.select(kg)
                editor.pickSlot(top)
                if editor.addOn(kg) == nil { editor.toggleAddOn() }
                editor.select(Cell(entry: entry.id, set: entry.sets[2].id, field: .reps))
                editor.key(.digit(1))
                editor.key(.digit(2))
                editor.select(nil)
                editor.toggleDone(entry.id, entry.sets[2].id)
                skipRest()
            }
        case "form":
            showWorkout = true
            if let editor, let entry = editor.workout.exercises.first {
                editor.editingExercise = ExerciseLink(id: entry.exerciseId)
            }
        case "rest":
            showWorkout = true
            restLength = settings.restSeconds
            restEnd = Date().addingTimeInterval(87)
        case "save":
            showWorkout = true
            editor?.saving = true
        case "picker":
            showWorkout = true
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
