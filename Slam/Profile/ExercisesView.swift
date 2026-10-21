import SwiftUI
import Charts
import SlamCore

struct ExercisesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ExerciseFilter()
    @State private var creating = false

    var body: some View {
        let list = filter.apply(model.exercises).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        List {
            ForEach(list) { e in
                NavigationLink(value: ExerciseLink(id: e.id)) { ExerciseRow(exercise: e) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                    .listRowBackground(Theme.bg)
                    .listRowSeparatorTint(Theme.line)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .searchable(text: $filter.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercise")
        .safeAreaInset(edge: .top, spacing: 0) { FilterBar(filter: $filter).background(Theme.bg) }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Create") { creating = true } }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                ExerciseForm(exercise: Exercise(name: filter.search), isNew: true) { model.save(exercise: $0) }
            }
            .environment(model)
        }
    }
}

/// One exercise: graph by gym, records, set records, and every session.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let id: UUID
    /// 0 Summary, 1 History.
    @State private var page: Int
    @State private var metric: Metric?
    @State private var range: Span = .all
    @State private var selected: Date?
    @State private var editing = false

    init(id: UUID, page: Int = 0) {
        self.id = id
        _page = State(initialValue: page)
    }

    enum Span: CaseIterable {
        case all, year, months3

        var title: String {
            switch self {
            case .all: "All time"
            case .year: "Last year"
            case .months3: "Last 3 months"
            }
        }

        var start: Date? {
            switch self {
            case .all: nil
            case .year: Calendar.current.date(byAdding: .year, value: -1, to: Date())
            case .months3: Calendar.current.date(byAdding: .month, value: -3, to: Date())
            }
        }
    }

    var body: some View {
        let ex = model.byId[id] ?? Exercise(id: id, name: "Deleted exercise")
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("", selection: $page) {
                    Text("Summary").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                if page == 0 { summary(ex) } else { history(ex) }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(ex.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ExerciseForm(exercise: ex, isNew: false) { model.save(exercise: $0) }
            }
            .environment(model)
        }
    }

    // MARK: Summary

    @ViewBuilder
    private func summary(_ ex: Exercise) -> some View {
        HStack(spacing: 14) {
            Thumb(exercise: ex, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(ex.name).font(.title3.weight(.semibold))
                Text("Primary: " + ex.primary.title).font(.subheadline).foregroundStyle(Theme.grey)
                HStack(spacing: 6) {
                    if !ex.brand.isEmpty { Tag(text: ex.brand) }
                    Tag(text: ex.equipment.title)
                    if ex.unilateral { Tag(text: "L / R") }
                }
            }
        }
        let metrics = Metric.available(for: ex.type)
        if let m = metric ?? metrics.first {
            chart(ex, m)
            Chips(options: metrics, selection: Binding(get: { m }, set: { metric = $0 }), title: \.title)
        }
        records(ex)
    }

    private func chart(_ ex: Exercise, _ m: Metric) -> some View {
        let all = Stats.series(ex.id, model.workouts, metric: m, type: ex.type)
        let points = range.start.map { s in all.filter { $0.date >= s } } ?? all
        let focus = selected.flatMap { d in points.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } } ?? points.last
        let gyms = Array(Set(points.map { gymName($0.gymId) })).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if let focus {
                    NavigationLink(value: WorkoutLink(id: focus.workoutId)) {
                        ChartHeader(value: value(focus.value, m),
                                    detail: focus.date.formatted(.dateTime.day().month(.abbreviated).year()) + " · " + gymName(focus.gymId))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Menu {
                    ForEach(Span.allCases, id: \.self) { s in
                        Button(s.title) { range = s }
                    }
                } label: {
                    Label(range.title, systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
            }
            if points.isEmpty {
                EmptyStats(title: range == .all ? "Not done yet" : "Not done in this time", icon: "chart.xyaxis.line")
                    .frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            } else {
                plot(points, focus, gyms, m)
            }
        }
    }

    private func plot(_ points: [Point], _ focus: Point?, _ gyms: [String], _ m: Metric) -> some View {
        Chart {
            if selected != nil, let focus {
                RuleMark(x: .value("Date", focus.date)).foregroundStyle(Theme.control)
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(m.title, p.value))
                    .foregroundStyle(Theme.blue.opacity(0.5))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                PointMark(x: .value("Date", p.date), y: .value(m.title, p.value))
                    .foregroundStyle(by: .value("Gym", gymName(p.gymId)))
                    .symbolSize(p.id == focus?.id ? 90 : 36)
            }
        }
        .chartForegroundStyleScale(domain: gyms, range: gyms.indices.map { Self.gymColors[$0 % Self.gymColors.count] })
        .chartLegend(gyms.count > 1 ? .visible : .hidden)
        .chartXSelection(value: $selected)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel()
            }
        }
        .frame(height: 200)
    }

    static let gymColors: [Color] = [Theme.blue, Theme.warm, Theme.green, Theme.rir, Theme.red]

    private func gymName(_ id: UUID?) -> String { model.gym(id)?.name ?? "No gym" }

    private func value(_ v: Double, _ m: Metric) -> String {
        switch m {
        case .heaviest, .e1rm, .bestSet, .session: Format.kg(v.rounded(toPlaces: 1)) + " kg"
        case .reps: "\(Int(v)) reps"
        case .seconds: Format.duration(v)
        case .meters: Format.km(v) + " km"
        }
    }

    @ViewBuilder
    private func records(_ ex: Exercise) -> some View {
        let b = Records.bests(ex.id, type: ex.type, in: model.workouts)
        let rows = recordRows(b, ex)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Personal Records", systemImage: "medal.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(rows) { r in
                    HStack {
                        Text(r.id).foregroundStyle(Theme.grey)
                        Spacer()
                        Text(r.value).font(.body.weight(.semibold)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        if !b.bySet.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set Records").font(.headline)
                ForEach(Array(b.bySet.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Text("Set \(i + 1)").foregroundStyle(Theme.grey)
                        Spacer()
                        Text(SetText.describe(s, ex)).font(.body.weight(.semibold)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    struct RecordRow: Identifiable {
        let id: String
        let value: String
    }

    private func recordRows(_ b: Bests, _ ex: Exercise) -> [RecordRow] {
        var out: [RecordRow] = []
        if let s = b.heaviest, let kg = s.kg { out.append(RecordRow(id: "Heaviest Weight", value: Format.kg(kg) + " kg")) }
        if let s = b.e1rm, let e = SetMath.e1rm(s) { out.append(RecordRow(id: "Best 1RM", value: Format.kg(e.rounded(toPlaces: 1)) + " kg")) }
        if let s = b.setVolume, ex.type.hasReps, SetMath.volume(s, ex.type) > 0 {
            out.append(RecordRow(id: "Best Set Volume", value: SetText.describe(s, ex)))
        }
        if b.sessionVolume > 0 { out.append(RecordRow(id: "Best Session Volume", value: Format.volume(b.sessionVolume))) }
        if !ex.type.hasKg, let s = b.reps { out.append(RecordRow(id: "Most Reps", value: String(SetMath.reps(s)))) }
        if let s = b.seconds?.seconds { out.append(RecordRow(id: "Longest Time", value: Format.clock(s))) }
        if let m = b.meters?.meters { out.append(RecordRow(id: "Longest Distance", value: Format.km(m) + " km")) }
        return out
    }

    // MARK: History

    struct Session: Identifiable {
        let w: Workout
        let e: WorkoutExercise
        var id: UUID { w.id }
    }

    @ViewBuilder
    private func history(_ ex: Exercise) -> some View {
        let sessions = model.workouts.compactMap { w in w.exercises.first { $0.exerciseId == ex.id }.map { Session(w: w, e: $0) } }
        if sessions.isEmpty {
            Text("Not done yet").foregroundStyle(Theme.grey).frame(maxWidth: .infinity, minHeight: 120)
        }
        ForEach(sessions) { session in
            let w = session.w, e = session.e
            let records = model.entryRecords(w, e)
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: WorkoutLink(id: w.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.title.isEmpty ? "Workout" : w.title).font(.body.weight(.semibold)).foregroundStyle(.white)
                            Text(w.start.dayTitle + (model.gym(w.gymId).map { " · " + $0.name } ?? ""))
                                .font(.footnote)
                                .foregroundStyle(Theme.grey)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let t = model.trend(w, e) { TrendBadge(trend: t) }
                    }
                }
                .buttonStyle(.plain)
                if !e.note.isEmpty { Text(e.note).font(.subheadline) }
                let settings = model.settingsText(e)
                if !settings.isEmpty { Text(settings).font(.footnote).foregroundStyle(Theme.grey) }
                SetGrid(entry: e, exercise: ex, records: records)
                RecordLine(records: records)
            }
            Divider().overlay(Theme.line)
        }
    }
}

extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let f = pow(10, Double(n))
        return (self * f).rounded() / f
    }
}
