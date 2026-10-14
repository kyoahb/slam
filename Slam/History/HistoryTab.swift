import SwiftUI
import SlamCore

struct HistoryTab: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var month: Date?

    struct MonthGroup: Identifiable {
        let id: Date
        let workouts: [Workout]
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.historyPath) {
            let groups = grouped(filtered)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.workouts) { w in
                                NavigationLink(value: WorkoutLink(id: w.id)) { WorkoutCard(workout: w) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text(g.id.formatted(.dateTime.month(.wide).year()))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.grey)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.bg)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .background(Theme.bg)
            .overlay {
                if model.workouts.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "clock.arrow.circlepath")
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search workouts")
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { monthMenu }
            }
            .appDestinations()
            .workoutBar()
        }
    }

    private var monthMenu: some View {
        Menu {
            Button {
                month = nil
            } label: {
                if month == nil { Label("All Time", systemImage: "checkmark") } else { Text("All Time") }
            }
            ForEach(months, id: \.self) { m in
                Button {
                    month = m
                } label: {
                    let name = m.formatted(.dateTime.month(.wide).year())
                    if month == m { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            if let month {
                Text(month.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "calendar")
            }
        }
        .accessibilityLabel("Filter by month")
    }

    private var months: [Date] {
        var seen = Set<Date>()
        return model.workouts.compactMap { w in
            let m = Self.monthStart(w.start)
            return seen.insert(m).inserted ? m : nil
        }
    }

    private var filtered: [Workout] {
        let words = search.lowercased().split(separator: " ")
        return model.workouts.filter { w in
            if let month, Self.monthStart(w.start) != month { return false }
            guard !words.isEmpty else { return true }
            let text = ([w.title, w.notes, model.gym(w.gymId)?.name ?? ""]
                + w.exercises.map { model.byId[$0.exerciseId]?.name ?? "" })
                .joined(separator: " ")
                .lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private func grouped(_ list: [Workout]) -> [MonthGroup] {
        var out: [MonthGroup] = []
        for w in list {
            let m = Self.monthStart(w.start)
            if let last = out.last, last.id == m {
                out[out.count - 1] = MonthGroup(id: m, workouts: last.workouts + [w])
            } else {
                out.append(MonthGroup(id: m, workouts: [w]))
            }
        }
        return out
    }

    static func monthStart(_ d: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: d)?.start ?? d
    }
}

/// Hevy's feed card: title, time, volume, records, photo, first exercises.
struct WorkoutCard: View {
    @Environment(AppModel.self) private var model
    let workout: Workout

    var body: some View {
        let records = model.records[workout.id]?.count ?? 0
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title.isEmpty ? "Workout" : workout.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.grey)
                    .lineLimit(1)
            }
            HStack(spacing: 28) {
                StatColumn(title: "Time", value: Format.duration(workout.duration))
                StatColumn(title: "Volume", value: Format.volume(Stats.volume(workout, model.byId)))
                if records > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Records").font(.caption).foregroundStyle(Theme.grey)
                        Label(String(records), systemImage: "medal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.medal)
                    }
                }
                Spacer(minLength: 0)
            }
            if let photo = workout.photos.first {
                Color.clear
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .overlay { StoredImage(file: photo.file) }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if workout.photos.count > 1 {
                            Text("+\(workout.photos.count - 1)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .padding(8)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(workout.exercises.prefix(3)) { e in
                    HStack(spacing: 10) {
                        Thumb(exercise: model.byId[e.exerciseId], size: 32)
                        Text("\(e.sets.count) \(e.sets.count == 1 ? "set" : "sets") \(model.byId[e.exerciseId]?.name ?? "Deleted exercise")")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                if workout.exercises.count > 3 {
                    let more = workout.exercises.count - 3
                    Text("See \(more) more \(more == 1 ? "exercise" : "exercises")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.grey)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let day = workout.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) + ", " + workout.start.time
        guard let gym = model.gym(workout.gymId)?.name else { return day }
        return day + " · " + gym
    }
}

extension View {
    /// Workout and exercise pages, reachable from both History and Profile.
    func appDestinations() -> some View {
        navigationDestination(for: WorkoutLink.self) { WorkoutDetailView(id: $0.id) }
            .navigationDestination(for: ExerciseLink.self) { ExerciseDetailView(id: $0.id) }
    }
}
