import Foundation

public actor HealthKitGoalStore {
    private let configuration: Configuration
    private let healthStore: any HealthStoreProviding
    private var state: PersistedState?
    private var sessions: [UUID: Task<Void, Never>] = [:]

    public init(configuration: Configuration = .default) {
        self.init(configuration: configuration, healthStore: LiveHealthStore())
    }

    public init(configuration: Configuration = .default, healthStore: any HealthStoreProviding) {
        self.configuration = configuration
        self.healthStore = healthStore
    }

    deinit {
        for session in sessions.values {
            session.cancel()
        }
    }

    public static func preview(totals: [GoalMetric: Double] = [:]) -> HealthKitGoalStore {
        HealthKitGoalStore(
            configuration: .init(debounceInterval: .milliseconds(100), snapshotStore: InMemorySnapshotStore()),
            healthStore: StubHealthStore(totals: totals)
        )
    }

    public var isHealthDataAvailable: Bool {
        get async { await healthStore.isHealthDataAvailable }
    }

    public func authorizationStatus(for goals: [GoalDefinition]) async -> AuthorizationSummary {
        let available = await healthStore.isHealthDataAvailable
        let requested = await currentState().requestedMetrics
        var statuses: [GoalMetric: MetricAuthorization] = [:]
        for metric in goals.metrics {
            if metric.isWritable {
                statuses[metric] = await healthStore.writeAuthorizationStatus(for: metric)
            } else {
                statuses[metric] = requested.contains(metric) ? .requested : .notRequested
            }
        }
        return AuthorizationSummary(statuses: statuses, isHealthDataAvailable: available)
    }

    public func requestAuthorization(for goals: [GoalDefinition]) async throws {
        guard await healthStore.isHealthDataAvailable else {
            throw HealthKitGoalError.healthDataUnavailable
        }
        let metrics = goals.metrics
        guard !metrics.isEmpty else { return }

        try await healthStore.requestAuthorization(
            read: metrics,
            write: Set(metrics.filter(\.isWritable))
        )
        await mutateState { $0.requestedMetrics.formUnion(metrics) }
        Log.store.info("Requested authorization for \(metrics.count, privacy: .public) metric(s).")
    }

    public func progress(for goal: GoalDefinition, on date: Date) async throws -> GoalProgress {
        try await progress(for: goal, on: date, in: await currentState())
    }

    public func snapshot(for goals: [GoalDefinition], on date: Date) async throws -> DailySnapshot {
        let state = await currentState()
        let day = configuration.calendar.goalDayInterval(containing: date)

        let progress = try await withThrowingTaskGroup(of: (Int, GoalProgress).self) { group in
            for (index, goal) in goals.enumerated() {
                group.addTask {
                    (index, try await self.progress(for: goal, on: date, in: state))
                }
            }
            var collected: [(Int, GoalProgress)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let snapshot = DailySnapshot(date: day.start, progress: progress)
        await mutateState { $0.lastSnapshot = snapshot }
        return snapshot
    }

    public func cachedSnapshot() async -> DailySnapshot? {
        await currentState().lastSnapshot
    }

    public func liveSnapshots(for goals: [GoalDefinition]) -> AsyncStream<DailySnapshot> {
        let (stream, continuation) = AsyncStream<DailySnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runSession(id: id, goals: goals, continuation: continuation)
        }
        sessions[id] = task
        continuation.onTermination = { [weak self] _ in
            task.cancel()
            Task { await self?.endSession(id) }
        }
        return stream
    }

    public func log(_ amount: Double, for metric: GoalMetric, at date: Date) async throws {
        guard await healthStore.isHealthDataAvailable else {
            throw HealthKitGoalError.healthDataUnavailable
        }
        guard metric.isWritable else {
            throw HealthKitGoalError.writeNotPermitted(metric)
        }
        guard amount > 0 else { return }
        try await healthStore.write(amount, for: metric, at: date)
        Log.store.info("Logged \(amount, privacy: .public) \(metric.displayUnitLabel, privacy: .public) of \(metric.rawValue, privacy: .public).")
    }

    public func dayKey(for date: Date) -> String {
        configuration.calendar.goalDayKey(for: date)
    }

    public func todayFractions(for goals: [GoalDefinition]) async throws -> [GoalDefinition.ID: Double] {
        try await snapshot(for: goals, on: Date()).fractionsByGoal
    }

    private func progress(
        for goal: GoalDefinition,
        on date: Date,
        in state: PersistedState
    ) async throws -> GoalProgress {
        let metric = goal.metric
        let day = configuration.calendar.goalDayInterval(containing: date)

        guard await healthStore.isHealthDataAvailable else {
            return .zero(for: goal, on: date, unavailableReason: .metricUnavailableOnDevice)
        }
        guard state.requestedMetrics.contains(metric) || metric.isWritable else {
            return .zero(for: goal, on: date, unavailableReason: .authorizationNotRequested)
        }
        if metric.isWritable, await healthStore.writeAuthorizationStatus(for: metric) == .denied {
            return .zero(for: goal, on: date, unavailableReason: .authorizationDenied)
        }

        let total = try await healthStore.total(for: metric, from: day.start, to: day.end)
        guard let total else {
            return .zero(for: goal, on: date, unavailableReason: .metricUnavailableOnDevice)
        }
        return GoalProgress(
            goalID: goal.id,
            value: total,
            target: goal.target,
            lastUpdated: Date(),
            unavailableReason: total > 0 ? nil : .noSamples
        )
    }

    private enum LiveEvent: Sendable {
        case healthChanged
        case dayChanged
    }

    private func runSession(
        id: UUID,
        goals: [GoalDefinition],
        continuation: AsyncStream<DailySnapshot>.Continuation
    ) async {
        let metrics = goals.metrics
        let (events, eventContinuation) = AsyncStream<LiveEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        await emit(goals: goals, to: continuation)

        var token: HealthObservationToken?
        if !metrics.isEmpty {
            do {
                token = try await healthStore.observe(metrics) {
                    eventContinuation.yield(.healthChanged)
                }
                if configuration.enablesBackgroundDelivery {
                    try await healthStore.setBackgroundDelivery(enabled: true, for: metrics)
                }
            } catch {
                Log.queries.error("Live updates unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        let dayWatcher = Task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                eventContinuation.yield(.dayChanged)
            }
        }

        var debounced: Task<Void, Never>?
        for await event in events {
            if Task.isCancelled { break }
            if case .dayChanged = event {
                continuation.yield(.empty(for: goals, on: configuration.calendar.startOfDay(for: Date())))
            }
            debounced?.cancel()
            debounced = Task { [weak self, interval = configuration.debounceInterval] in
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await self?.emit(goals: goals, to: continuation)
            }
        }

        debounced?.cancel()
        dayWatcher.cancel()
        eventContinuation.finish()
        token?.cancel()
        if configuration.enablesBackgroundDelivery, !metrics.isEmpty {
            try? await healthStore.setBackgroundDelivery(enabled: false, for: metrics)
        }
        continuation.finish()
    }

    private func emit(goals: [GoalDefinition], to continuation: AsyncStream<DailySnapshot>.Continuation) async {
        do {
            continuation.yield(try await snapshot(for: goals, on: Date()))
        } catch {
            Log.queries.error("Snapshot refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endSession(_ id: UUID) {
        sessions.removeValue(forKey: id)?.cancel()
    }

    private func currentState() async -> PersistedState {
        if let state { return state }
        let loaded: PersistedState
        do {
            loaded = try await configuration.snapshotStore.load()
        } catch {
            Log.persistence.error("Cache unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            loaded = PersistedState()
        }
        state = loaded
        return loaded
    }

    private func mutateState(_ body: @Sendable (inout PersistedState) -> Void) async {
        var updated = await currentState()
        body(&updated)
        state = updated
        do {
            try await configuration.snapshotStore.save(updated)
        } catch {
            Log.persistence.error("Cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
