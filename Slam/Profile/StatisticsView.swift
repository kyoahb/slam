import SwiftUI
import Charts
import SlamCore

/// Hevy's statistics page: the last 7 days, sets per muscle in them, then the deeper pages.
struct StatisticsView: View {
    @Environment(AppModel.self) private var model
    private let calendar = Stats.mondayCalendar()

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: today) }
        let worked = Set(model.workouts.map { calendar.startOfDay(for: $0.start) })
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let rows = Stats.setsPerMuscle(model.workouts, model.byId, from: days[0], to: end)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Last 7 days").font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { d in
                            dayTile(d, worked: worked.contains(d), today: d == today)
                        }
                    }
                    if rows.isEmpty {
                        Text("No workouts in the last 7 days")
                            .font(.subheadline)
                            .foregroundStyle(Theme.grey)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        MuscleBars(rows: rows)
                    }
                }
                .padding(16)
                Text("Advanced statistics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.grey)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                link("Volume", "chart.bar.xaxis", .volume)
                link("Sets per muscle group", "figure.strengthtraining.traditional", .muscles)
                link("Main exercises", "dumbbell", .mainExercises)
            }
        }
        .background(Theme.bg)
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: StatsRoute.self) { route in
            switch route {
            case .volume: VolumeStatsView()
            case .muscles: MuscleSetsView()
            case .mainExercises: MainExercisesView()
            }
        }
    }

    private func dayTile(_ d: Date, worked: Bool, today: Bool) -> some View {
        VStack(spacing: 6) {
            Text(d.formatted(.dateTime.weekday(.narrow)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.grey)
            Text(d.formatted(.dateTime.day()))
                .font(.subheadline.weight(worked ? .semibold : .regular))
                .foregroundStyle(worked ? .white : Theme.grey)
                .frame(width: 32, height: 32)
                .background(Circle().fill(worked ? Theme.blue : .clear))
            Circle().fill(today ? Theme.blue : .clear).frame(width: 4, height: 4)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
    }

    private func link(_ title: String, _ icon: String, _ route: StatsRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 30)
                Text(title).font(.body)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.grey)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 60) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum StatsRoute: Hashable {
    case volume, muscles, mainExercises
}

/// Sets per primary muscle, longest bar first, with the count at the end.
struct MuscleBars: View {
    let rows: [(muscle: Muscle, sets: Int)]

    var body: some View {
        let top = max(1, rows.map(\.sets).max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.muscle) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.muscle.title).font(.subheadline)
                    HStack(spacing: 8) {
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.blue)
                                .frame(width: max(6, g.size.width * CGFloat(r.sets) / CGFloat(top)))
                        }
                        .frame(height: 12)
                        Text(r.sets == 1 ? "1 set" : "\(r.sets) sets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.grey)
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Volume or sets for each workout and each week. Tap a bar for its numbers, then the numbers to open it.
struct VolumeStatsView: View {
    @Environment(AppModel.self) private var model
    @State private var perWorkout: PerWorkout = .volume
    @State private var selected: Date?

    enum PerWorkout: CaseIterable {
        case volume, sets

        var title: String { self == .volume ? "Volume" : "Sets" }
    }

    struct Bar: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private let calendar = Stats.mondayCalendar()

    var body: some View {
        ScrollView {
            if model.workouts.isEmpty {
                EmptyStats(title: "No workouts yet", icon: "chart.bar.xaxis").padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Per workout").font(.headline)
                        workoutChart
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Per week").font(.headline)
                        WeekChart(weeks: Stats.weeks(model.workouts, model.byId))
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .navigationTitle("Volume")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bars: [Bar] {
        model.workouts.reversed().map { w in
            Bar(id: w.id, date: w.start,
                value: perWorkout == .volume ? Stats.volume(w, model.byId) : Double(SetMath.workingCount(w)))
        }
    }

    private var workoutChart: some View {
        let list = bars
        let picked = selected.flatMap { d in
            list.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }
        }
        let focus = picked ?? list.last
        return VStack(alignment: .leading, spacing: 12) {
            if let focus {
                NavigationLink(value: WorkoutLink(id: focus.id)) {
                    ChartHeader(value: perWorkout == .volume ? Format.volume(focus.value) : "\(Int(focus.value)) sets",
                                detail: (model.workout(focus.id)?.title ?? "Workout") + " · " + focus.date.shortDay)
                }
                .buttonStyle(.plain)
            }
            Chart(list) { b in
                BarMark(x: .value("Day", b.date, unit: .day, calendar: calendar), y: .value(perWorkout.title, b.value))
                    .foregroundStyle(picked == nil || b.id == focus?.id ? Theme.blue : Theme.blue.opacity(0.5))
                    .cornerRadius(2)
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 3600 * 24 * 42)
            .chartScrollPosition(initialX: calendar.date(byAdding: .day, value: -41, to: list.last?.date ?? Date()) ?? Date())
            .chartXSelection(value: $selected)
            .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    AxisGridLine().foregroundStyle(Theme.line)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel()
                }
            }
            .frame(height: 200)
            Chips(options: PerWorkout.allCases, selection: $perWorkout, title: \.title)
        }
    }
}

/// Working sets per muscle, a week at a time.
struct MuscleSetsView: View {
    @Environment(AppModel.self) private var model
    @State private var weekOffset = 0
    private let calendar = Stats.mondayCalendar()

    var body: some View {
        let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Stats.weekStart(Date(), calendar)) ?? Date()
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        let rows = Stats.setsPerMuscle(model.workouts, model.byId, from: start, to: end)
        let first = model.workouts.last.map { Stats.weekStart($0.start, calendar) } ?? start
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                        .disabled(start <= first)
                    Spacer()
                    Text(weekOffset == 0 ? "This week" : start.shortDay + " – " + (calendar.date(byAdding: .day, value: 6, to: start) ?? start).shortDay)
                        .font(.headline)
                    Spacer()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                        .disabled(weekOffset >= 0)
                }
                if rows.isEmpty {
                    EmptyStats(title: "No sets this week", icon: "figure.strengthtraining.traditional").padding(.top, 40)
                } else {
                    MuscleBars(rows: rows)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Sets per Muscle Group")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The exercises done most often.
struct MainExercisesView: View {
    @Environment(AppModel.self) private var model

    struct Row: Identifiable {
        let id: UUID
        let count: Int
        let last: Date
    }

    var body: some View {
        let rows = mainRows
        ScrollView {
            if rows.isEmpty {
                EmptyStats(title: "No exercises logged yet", icon: "dumbbell").padding(.top, 80)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { r in
                        NavigationLink(value: ExerciseLink(id: r.id)) {
                            HStack(spacing: 12) {
                                Thumb(exercise: model.byId[r.id], size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.byId[r.id]?.name ?? "Deleted exercise")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("Last " + r.last.relativeDay).font(.footnote).foregroundStyle(Theme.grey)
                                }
                                Spacer(minLength: 4)
                                Text(r.count == 1 ? "1 workout" : "\(r.count) workouts")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.grey)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 72) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Main Exercises")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mainRows: [Row] {
        var counts: [UUID: (Int, Date)] = [:]
        for w in model.workouts {
            for id in Set(w.exercises.map(\.exerciseId)) {
                let c = counts[id] ?? (0, w.start)
                counts[id] = (c.0 + 1, max(c.1, w.start))
            }
        }
        return counts.map { Row(id: $0.key, count: $0.value.0, last: $0.value.1) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
            .prefix(15)
            .map { $0 }
    }
}

/// The big number and what it is, over a chart. A chevron when tapping it opens something.
struct ChartHeader: View {
    let value: String
    let detail: String
    var opens = true

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                Text(detail).font(.footnote).foregroundStyle(Theme.grey).lineLimit(1)
            }
            if opens {
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.grey)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// A quiet empty state that keeps the page's shape.
struct EmptyStats: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.dim)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.grey)
        }
        .frame(maxWidth: .infinity)
    }
}

extension SetMath {
    static func workingCount(_ w: Workout) -> Int {
        w.exercises.reduce(0) { $0 + working($1).count }
    }
}
