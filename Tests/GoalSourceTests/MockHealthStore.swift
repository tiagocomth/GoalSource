import Foundation
@testable import GoalSource

actor MockHealthStore: HealthStoreProviding {
    var isAvailable = true
    var totals: [GoalMetric: Double?] = [:]
    var writeStatuses: [GoalMetric: MetricAuthorization] = [:]
    var authorizationError: (any Error)?
    var totalError: (any Error)?

    private(set) var requestedRead: Set<GoalMetric> = []
    private(set) var requestedWrite: Set<GoalMetric> = []
    private(set) var authorizationCallCount = 0
    private(set) var writes: [(amount: Double, metric: GoalMetric, date: Date)] = []
    private(set) var totalQueries: [(metric: GoalMetric, start: Date, end: Date)] = []
    private(set) var backgroundDeliveryCalls: [(enabled: Bool, metrics: Set<GoalMetric>)] = []
    private(set) var observedMetrics: Set<GoalMetric> = []
    private(set) var cancelledObservations = 0

    private var onChange: (@Sendable () -> Void)?

    func setAvailable(_ available: Bool) { isAvailable = available }
    func setTotal(_ total: Double?, for metric: GoalMetric) { totals[metric] = total }
    func setWriteStatus(_ status: MetricAuthorization, for metric: GoalMetric) { writeStatuses[metric] = status }
    func setTotalError(_ error: (any Error)?) { totalError = error }

    func fireChange() { onChange?() }

    var isObserving: Bool { onChange != nil }

    var isHealthDataAvailable: Bool {
        get async { isAvailable }
    }

    func requestAuthorization(read: Set<GoalMetric>, write: Set<GoalMetric>) async throws {
        authorizationCallCount += 1
        if let authorizationError { throw authorizationError }
        requestedRead.formUnion(read)
        requestedWrite.formUnion(write)
    }

    func writeAuthorizationStatus(for metric: GoalMetric) async -> MetricAuthorization {
        writeStatuses[metric] ?? .notRequested
    }

    func total(for metric: GoalMetric, from start: Date, to end: Date) async throws -> Double? {
        totalQueries.append((metric, start, end))
        if let totalError { throw totalError }
        return totals[metric] ?? 0
    }

    func write(_ amount: Double, for metric: GoalMetric, at date: Date) async throws {
        writes.append((amount, metric, date))
    }

    func observe(
        _ metrics: Set<GoalMetric>,
        onChange: @escaping @Sendable () -> Void
    ) async throws -> HealthObservationToken {
        observedMetrics = metrics
        self.onChange = onChange
        return HealthObservationToken {
            Task { await self.markCancelled() }
        }
    }

    func setBackgroundDelivery(enabled: Bool, for metrics: Set<GoalMetric>) async throws {
        backgroundDeliveryCalls.append((enabled, metrics))
    }

    private func markCancelled() {
        cancelledObservations += 1
        onChange = nil
    }
}

enum Fixture {
    static func goal(
        _ title: String = "Meta",
        target: Double = 10,
        metric: GoalMetric = .stepCount,
        id: String = UUID().uuidString
    ) -> GoalDefinition {
        GoalDefinition(id: id, title: title, target: target, metric: metric)
    }

    static func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static let noon = Date(timeIntervalSince1970: 1_787_238_000)
}
