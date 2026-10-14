import HealthKit
import SlamCore

extension AppModel {
    /// Links Apple Watch workouts to cardio: once Health has a Watch workout that happened during the workout
    /// in progress (or one finished in the last few hours), it goes on the cardio exercise it fits.
    /// Health access is asked for the first time there is cardio to link.
    func checkWatch() {
        guard !demo, HKHealthStore.isHealthDataAvailable(), !watchTargets.isEmpty else { return }
        Task { await WatchLinker.shared.scan(self) }
    }

    /// Workouts with cardio still waiting for its Watch workout.
    var watchTargets: [Workout] {
        let since = Date().addingTimeInterval(-WatchLinker.lookBack)
        let list = (editor.map { [$0.workout] } ?? []) + workouts.filter { ($0.end ?? $0.start) > since }
        return list.filter { w in
            w.exercises.contains { $0.watch == nil && !(byId[$0.exerciseId]?.watchActivities.isEmpty ?? true) }
        }
    }
}

@MainActor
final class WatchLinker {
    static let shared = WatchLinker()
    /// How far back a finished workout can still take its Watch workout.
    static let lookBack: TimeInterval = 6 * 3600
    /// A Watch workout may start a little before the Slam workout does.
    static let slack: TimeInterval = 15 * 60

    private let health = HKHealthStore()
    private var observing = false
    private var scanning = false

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
        HKQuantityType(.distanceRowing),
    ]

    func scan(_ model: AppModel) async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        guard (try? await health.requestAuthorization(toShare: [], read: readTypes)) != nil else { return }
        observe(model)
        guard let earliest = model.watchTargets.map(\.start).min() else { return }
        var linked = Set(model.workouts.flatMap(\.watchIds))
        if let editor = model.editor { linked.formUnion(editor.workout.watchIds) }
        for hk in await workouts(since: earliest.addingTimeInterval(-Self.slack)) where !linked.contains(hk.uuid) {
            guard let activity = Self.activity(hk.workoutActivityType) else { continue }
            let link = Self.link(hk)
            if let editor = model.editor, Self.during(hk, editor.workout),
               editor.workout.link(link, as: activity, exercises: model.byId) {
                editor.changed()
                model.refreshLiveActivity()
                continue
            }
            if var w = model.watchTargets.first(where: { $0.end != nil && Self.during(hk, $0) }),
               w.link(link, as: activity, exercises: model.byId) {
                model.insert(w)
            }
        }
    }

    /// New Watch workouts reach the phone a little after they end; look again each time one arrives.
    private func observe(_ model: AppModel) {
        guard !observing else { return }
        observing = true
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { _, done, _ in
            Task { @MainActor in model.checkWatch() }
            done()
        }
        health.execute(query)
    }

    private func workouts(since start: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        return (try? await query.result(for: health)) ?? []
    }

    private static func during(_ hk: HKWorkout, _ w: Workout) -> Bool {
        hk.startDate >= w.start.addingTimeInterval(-slack) && hk.startDate <= (w.end ?? Date())
    }

    private static func link(_ hk: HKWorkout) -> WatchLink {
        let meters = hk.allStatistics
            .filter { $0.key.identifier.hasPrefix("HKQuantityTypeIdentifierDistance") }
            .compactMap { $0.value.sumQuantity()?.doubleValue(for: .meter()) }
            .reduce(0, +)
        return WatchLink(id: hk.uuid, start: hk.startDate, end: hk.endDate, meters: meters > 0 ? meters : nil,
                         kcal: hk.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                         heartRate: hk.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?
                            .doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
    }

    private static func activity(_ type: HKWorkoutActivityType) -> WatchActivity? {
        switch type {
        case .elliptical: .elliptical
        case .stairClimbing, .stairs, .stepTraining: .stairs
        case .rowing: .rowing
        case .cycling: .cycling
        case .running: .running
        case .walking, .hiking: .walking
        case .swimming: .swimming
        default: nil
        }
    }
}
