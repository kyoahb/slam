import SwiftUI
import SlamCore

/// Every month since the first workout (a year at least), oldest first; workout days are filled in.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    private let calendar = Stats.mondayCalendar()

    var body: some View {
        let dates = model.workouts.map(\.start)
        let byDay = Dictionary(grouping: model.workouts) { calendar.startOfDay(for: $0.start) }
        let months = monthList(dates)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(months, id: \.self) { m in
                    MonthGrid(month: m, calendar: calendar, byDay: byDay)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .defaultScrollAnchor(.bottom)
        .background(Theme.bg)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    let streak = Stats.weekStreak(dates)
                    let rest = Stats.restDays(dates)
                    Label(streak == 1 ? "1 week streak" : "\(streak) week streak", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                    Rectangle().fill(Theme.line).frame(width: 1, height: 22)
                    Label(rest == 1 ? "1 rest day" : "\(rest) rest days", systemImage: "moon.fill")
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline.weight(.semibold))
                .labelStyle(TintedIcon())
                HStack(spacing: 0) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                        Text(d).frame(maxWidth: .infinity)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.grey)
                .padding(.horizontal, 12)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthList(_ dates: [Date]) -> [Date] {
        let now = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let yearAgo = calendar.date(byAdding: .month, value: -11, to: now) ?? now
        let first = dates.min().flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? now
        var out: [Date] = []
        var cursor = min(first, yearAgo)
        while cursor <= now {
            out.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}

/// Flame and moon in their own colours, the text white.
struct TintedIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.blue)
            configuration.title.foregroundStyle(.white)
        }
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
        let count = (1...days).reduce(0) { n, day in
            n + (calendar.date(byAdding: .day, value: day - 1, to: month).flatMap { byDay[$0]?.count } ?? 0)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                if count > 0 {
                    Text(count == 1 ? "1 workout" : "\(count) workouts").font(.footnote).foregroundStyle(Theme.grey)
                }
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach(1...days, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                    cell(day, byDay[date]?.first, today: calendar.isDateInToday(date))
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Int, _ w: Workout?, today: Bool) -> some View {
        let label = VStack(spacing: 2) {
            Text(String(day))
                .font(.subheadline.weight(w == nil ? .regular : .semibold))
                .foregroundStyle(w == nil ? (today ? Theme.blue : Theme.grey) : .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(w == nil ? .clear : Theme.blue))
                .overlay { if today && w == nil { Circle().strokeBorder(Theme.blue, lineWidth: 1.5) } }
            Text(w.map { $0.title.isEmpty ? "Workout" : $0.title } ?? " ")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.grey)
                .lineLimit(1)
                .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
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
