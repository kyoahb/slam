import SwiftUI
import Charts
import SlamCore

/// Set load per workout, per week, and working sets per muscle.
struct StatisticsView: View {
    @Environment(AppModel.self) private var model
    @State private var perWorkout: PerWorkout = .volume
    @State private var selected: Date?
    @State private var weekOffset = 0

    enum PerWorkout: CaseIterable {
        case volume, sets

        var title: String { self == .volume ? "Volume" : "Sets" }
    }

    struct MuscleRow: Identifiable {
        let muscle: Muscle
        let sets: Int
        var id: Muscle { muscle }
    }

    struct Bar: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private let calendar = Stats.mondayCalendar()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Set load per workout") { workoutChart }
                section("Set load per week") { WeekChart(weeks: Stats.weeks(model.workouts, model.byId)) }
                section("Sets per muscle") { muscles }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
    }

    private var bars: [Bar] {
        model.workouts.reversed().map { w in
            Bar(id: w.id, date: w.start,
                value: perWorkout == .volume ? Stats.volume(w, model.byId) : Double(SetMath.workingCount(w)))
        }
    }

    private var workoutChart: some View {
        let list = bars
        let focus = selected.flatMap { d in list.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } } ?? list.last
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.map { perWorkout == .volume ? Format.volume($0.value) : "\(Int($0.value)) sets" } ?? "–")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(focus.map { (model.workout($0.id)?.title ?? "") + " · " + $0.date.shortDay } ?? "No workouts yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.grey)
                    .lineLimit(1)
            }
            Chart(list) { b in
                BarMark(x: .value("Day", b.date, unit: .day, calendar: calendar), y: .value(perWorkout.title, b.value))
                    .foregroundStyle(b.id == focus?.id ? Theme.blue : Theme.blue.opacity(0.45))
                    .cornerRadius(2)
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 3600 * 24 * 42)
            .chartScrollPosition(initialX: calendar.date(byAdding: .day, value: -41, to: list.last?.date ?? Date()) ?? Date())
            .chartXSelection(value: $selected)
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
            .frame(height: 180)
            Chips(options: PerWorkout.allCases, selection: $perWorkout, title: \.title)
        }
    }

    private var muscles: some View {
        let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Stats.weekStart(Date(), calendar)) ?? Date()
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        let rows = Stats.setsPerMuscle(model.workouts, model.byId, from: start, to: end).map { MuscleRow(muscle: $0.muscle, sets: $0.sets) }
        let first = model.workouts.last.map { Stats.weekStart($0.start, calendar) } ?? start
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 36, height: 32) }
                    .disabled(start <= first)
                Spacer()
                Text(weekOffset == 0 ? "This week" : start.shortDay + " – " + (calendar.date(byAdding: .day, value: 6, to: start) ?? start).shortDay)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 36, height: 32) }
                    .disabled(weekOffset >= 0)
            }
            if rows.isEmpty {
                Text("No sets this week").font(.subheadline).foregroundStyle(Theme.grey)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart(rows) { r in
                    BarMark(x: .value("Sets", r.sets), y: .value("Muscle", r.muscle.title))
                        .foregroundStyle(Theme.blue)
                        .cornerRadius(3)
                        .annotation(position: .trailing) {
                            Text(String(r.sets)).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel().foregroundStyle(.white) }
                }
                .frame(height: CGFloat(rows.count) * 30 + 10)
            }
        }
    }
}

extension SetMath {
    static func workingCount(_ w: Workout) -> Int {
        w.exercises.reduce(0) { $0 + working($1).count }
    }
}
