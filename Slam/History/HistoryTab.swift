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
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.workouts) { w in
                                NavigationLink(value: WorkoutLink(id: w.id)) { WorkoutCard(workout: w) }
                                    .buttonStyle(.plain)
                                Rectangle().fill(Theme.surface).frame(height: 8)
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

/// Hevy's feed card: title, when and where, time, volume, records, photo, the first three exercises.
struct WorkoutCard: View {
    @Environment(AppModel.self) private var model
    let workout: Workout

    var body: some View {
        let records = model.records[workout.id] ?? []
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title.isEmpty ? "Workout" : workout.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(workout.start.relativeDay + ", " + workout.start.time)
                        if let gym = model.gym(workout.gymId)?.name {
                            Text("·")
                            Image(systemName: "mappin.and.ellipse").font(.caption2)
                            Text(gym)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.grey)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                ShareLink(item: ShareText.workout(workout, model)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share workout")
            }
            HStack(spacing: 26) {
                StatColumn(title: "Time", value: Format.duration(workout.duration))
                StatColumn(title: "Volume", value: Format.volume(Stats.volume(workout, model.byId)))
                StatColumn(title: "Sets", value: String(Stats.sets(workout)))
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Records").font(.caption).foregroundStyle(Theme.grey)
                        Label(String(records.count), systemImage: "medal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.medal)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer(minLength: 0)
            }
            if let photo = workout.photos.first {
                Color.clear
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .overlay { StoredImage(file: photo.file) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(workout.exercises.prefix(3)) { e in
                    row(e, medal: records.contains { r in r.exerciseId == e.exerciseId })
                }
                if workout.exercises.count > 3 {
                    let more = workout.exercises.count - 3
                    Text("See \(more) more \(more == 1 ? "exercise" : "exercises")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.grey)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .contentShape(Rectangle())
    }

    /// "3 sets  Leg Extension" with the best set underneath.
    private func row(_ e: WorkoutExercise, medal: Bool) -> some View {
        let ex = model.byId[e.exerciseId]
        let best = ex.flatMap { x in SetMath.working(e).max { SetMath.score($0, x.type) < SetMath.score($1, x.type) } }
        return HStack(spacing: 12) {
            Thumb(exercise: ex, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? "Deleted exercise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(e.sets.count) \(e.sets.count == 1 ? "set" : "sets")")
                    if let best, let ex {
                        Text("·")
                        Text(SetText.describe(best, ex)).monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.grey)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if medal {
                Image(systemName: "medal.fill").font(.footnote).foregroundStyle(Theme.medal)
            }
        }
    }
}

extension View {
    /// Workout and exercise pages, reachable from both History and Profile.
    func appDestinations() -> some View {
        navigationDestination(for: WorkoutLink.self) { WorkoutDetailView(id: $0.id) }
            .navigationDestination(for: ExerciseLink.self) { ExerciseDetailView(id: $0.id) }
            .navigationDestination(for: WeekLink.self) { WeekView(start: $0.start) }
    }
}

/// One week's workouts, from a tapped bar.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    let start: Date

    var body: some View {
        let cal = Stats.mondayCalendar()
        let list = model.workouts.filter { Stats.weekStart($0.start, cal) == start }
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list) { w in
                    NavigationLink(value: WorkoutLink(id: w.id)) { WorkoutCard(workout: w) }.buttonStyle(.plain)
                    Rectangle().fill(Theme.surface).frame(height: 8)
                }
            }
        }
        .background(Theme.bg)
        .overlay { if list.isEmpty { EmptyStats(title: "No workouts this week", icon: "calendar") } }
        .navigationTitle(start.shortDay + " – " + end.shortDay)
        .navigationBarTitleDisplayMode(.inline)
    }
}
