import SwiftUI
import Charts
import SlamCore

struct ProfileTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.profilePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 28) {
                        StatColumn(title: "Workouts", value: String(model.workouts.count))
                        let streak = Stats.weekStreak(model.workouts.map(\.start))
                        StatColumn(title: "Streak", value: streak == 1 ? "1 week" : "\(streak) weeks")
                        Spacer()
                    }
                    WeekChart(weeks: Stats.weeks(model.workouts, model.byId))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dashboard").font(.subheadline).foregroundStyle(Theme.grey)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            tile("Statistics", "chart.bar.xaxis", .statistics)
                            tile("Exercises", "dumbbell", .exercises)
                            tile("Calendar", "calendar", .calendar)
                            tile("Photos", "photo.on.rectangle", .photos)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ProfileRoute.settings) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .statistics: StatisticsView()
                case .exercises: ExercisesView()
                case .calendar: CalendarView()
                case .photos: PhotosView()
                case .settings: SettingsView()
                }
            }
            .appDestinations()
            .workoutBar()
        }
    }

    private func tile(_ title: String, _ icon: String, _ route: ProfileRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }
}

/// Chip row for picking what a chart shows.
struct Chips<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    Button(title(o)) { selection = o }
                        .buttonStyle(PillButton(fill: o == selection ? Theme.blue : Theme.surface))
                }
            }
        }
    }
}

/// Every week since the first workout, scrollable; the header shows the week tapped (or this week).
struct WeekChart: View {
    enum Value: CaseIterable {
        case volume, sets, duration

        var title: String {
            switch self {
            case .volume: "Volume"
            case .sets: "Sets"
            case .duration: "Duration"
            }
        }
    }

    let weeks: [Week]
    var options: [Value] = Value.allCases
    @State private var value: Value = .volume
    @State private var selected: Date?

    private let calendar = Stats.mondayCalendar()

    var body: some View {
        let focus = focusWeek
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.map { text(number($0)) } ?? "–")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(focus.map(weekTitle) ?? "No workouts yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.grey)
            }
            Chart(weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear, calendar: calendar),
                        y: .value(value.title, number(w)))
                    .foregroundStyle(w.start == focus?.start ? Theme.blue : Theme.blue.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 3600 * 24 * 7 * 12)
            .chartScrollPosition(initialX: initialX)
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    AxisGridLine().foregroundStyle(Theme.line)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(short(d)) } }
                }
            }
            .frame(height: 180)
            Chips(options: options, selection: $value, title: \.title)
        }
    }

    private var focusWeek: Week? {
        if let selected {
            let start = Stats.weekStart(selected, calendar)
            if let w = weeks.first(where: { $0.start == start }) { return w }
        }
        return weeks.last
    }

    private var initialX: Date {
        guard let last = weeks.last?.start else { return Date() }
        return calendar.date(byAdding: .weekOfYear, value: -11, to: last) ?? last
    }

    private func number(_ w: Week) -> Double {
        switch value {
        case .volume: w.volume
        case .sets: Double(w.sets)
        case .duration: w.seconds / 3600
        }
    }

    private func text(_ n: Double) -> String {
        switch value {
        case .volume: Format.volume(n)
        case .sets: "\(Int(n)) sets"
        case .duration: Format.duration(n * 3600)
        }
    }

    private func short(_ n: Double) -> String {
        switch value {
        case .volume: n >= 1000 ? Format.kg((n / 100).rounded() / 10) + "k" : Format.kg(n)
        case .sets: Format.kg(n)
        case .duration: Format.kg(n) + "h"
        }
    }

    private func weekTitle(_ w: Week) -> String {
        if w.start == Stats.weekStart(Date(), calendar) { return "This week" }
        let end = calendar.date(byAdding: .day, value: 6, to: w.start) ?? w.start
        return w.start.shortDay + " – " + end.shortDay
    }
}
