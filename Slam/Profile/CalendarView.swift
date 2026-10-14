import SwiftUI
import SlamCore

/// Every month since the first workout; workout days are filled in.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    private let calendar = Stats.mondayCalendar()

    var body: some View {
        let dates = model.workouts.map(\.start)
        let byDay = Dictionary(grouping: model.workouts) { calendar.startOfDay(for: $0.start) }
        let months = monthList(dates)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(months, id: \.self) { m in
                        MonthGrid(month: m, calendar: calendar, byDay: byDay).id(m)
                    }
                }
                .padding(16)
            }
            .onAppear { if let last = months.last { proxy.scrollTo(last, anchor: .bottom) } }
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 28) {
                let streak = Stats.weekStreak(dates)
                let rest = Stats.restDays(dates)
                StatColumn(title: "Streak", value: streak == 1 ? "1 week" : "\(streak) weeks", tint: Theme.blue)
                StatColumn(title: "Rest", value: rest == 1 ? "1 day" : "\(rest) days")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthList(_ dates: [Date]) -> [Date] {
        let now = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        guard let first = dates.min().flatMap({ calendar.dateInterval(of: .month, for: $0)?.start }) else { return [now] }
        var out: [Date] = []
        var cursor = first
        while cursor <= now {
            out.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}

struct MonthGrid: View {
    let month: Date
    let calendar: Calendar
    let byDay: [Date: [Workout]]

    var body: some View {
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let offset = (calendar.component(.weekday, from: month) + 5) % 7
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(alignment: .leading, spacing: 10) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption.weight(.semibold)).foregroundStyle(Theme.grey)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...days, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                    cell(day, byDay[date]?.first)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Int, _ w: Workout?) -> some View {
        let label = Text(String(day))
            .font(.subheadline.weight(w == nil ? .regular : .semibold))
            .foregroundStyle(w == nil ? Theme.grey : .white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(w == nil ? .clear : Theme.blue))
            .frame(height: 38)
        if let w {
            NavigationLink(value: WorkoutLink(id: w.id)) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// Every photo attached to a workout, newest first.
struct PhotosView: View {
    @Environment(AppModel.self) private var model
    @State private var viewing: Photo?

    var body: some View {
        let photos = model.workouts.flatMap(\.photos).sorted { $0.addedAt > $1.addedAt }
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(photos) { p in
                    Button { viewing = p } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { StoredImage(file: p.file) }
                            .clipped()
                            .overlay(alignment: .bottomLeading) {
                                Text(p.addedAt.shortDay)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.black.opacity(0.6)))
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Theme.bg)
        .overlay {
            if photos.isEmpty { ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle") }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(photo: p).environment(model)
        }
    }
}
