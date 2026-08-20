import Foundation

#if canImport(HealthKit)
import HealthKit

public final class LiveHealthStore: HealthStoreProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    public var isHealthDataAvailable: Bool {
        get async { HKHealthStore.isHealthDataAvailable() }
    }

    public func requestAuthorization(read: Set<GoalMetric>, write: Set<GoalMetric>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitGoalError.healthDataUnavailable
        }
        var readTypes: Set<HKObjectType> = []
        for metric in read {
            guard let type = metric.quantityType else {
                throw HealthKitGoalError.unsupportedMetric(metric)
            }
            readTypes.insert(type)
            if metric.readsWorkouts {
                readTypes.insert(HKObjectType.workoutType())
            }
        }
        var shareTypes: Set<HKSampleType> = []
        for metric in write {
            guard metric.isWritable else { throw HealthKitGoalError.writeNotPermitted(metric) }
            guard let type = metric.quantityType else {
                throw HealthKitGoalError.unsupportedMetric(metric)
            }
            shareTypes.insert(type)
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            throw HealthKitGoalError.wrapping(error)
        }
    }

    public func writeAuthorizationStatus(for metric: GoalMetric) async -> MetricAuthorization {
        guard metric.isWritable, let type = metric.quantityType else { return .requested }
        switch store.authorizationStatus(for: type) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notRequested
        @unknown default: return .notRequested
        }
    }

    public func total(for metric: GoalMetric, from start: Date, to end: Date) async throws -> Double? {
        guard let type = metric.quantityType else { return nil }
        if metric.readsWorkouts {
            return try await runningDistance(type: type, unit: metric.preferredUnit, from: start, to: end)
        }
        return try await sum(of: type, unit: metric.preferredUnit, from: start, to: end)
    }

    private func sum(of type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let box = UncheckedBox((store: store, type: type, unit: unit, predicate: predicate))
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: box.value.type,
                quantitySamplePredicate: box.value.predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error, (error as NSError).code != HKError.errorNoData.rawValue {
                    continuation.resume(throwing: HealthKitGoalError.queryFailed(underlying: error.localizedDescription))
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: box.value.unit) ?? 0)
            }
            box.value.store.execute(query)
        }
    }

    private func runningDistance(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        ])
        let box = UncheckedBox((store: store, type: type, unit: unit, predicate: predicate))
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: box.value.predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error, (error as NSError).code != HKError.errorNoData.rawValue {
                    continuation.resume(throwing: HealthKitGoalError.queryFailed(underlying: error.localizedDescription))
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let total = workouts.reduce(0.0) { partial, workout in
                    let distance = workout.statistics(for: box.value.type)?.sumQuantity()
                    return partial + (distance?.doubleValue(for: box.value.unit) ?? 0)
                }
                continuation.resume(returning: total)
            }
            box.value.store.execute(query)
        }
    }

    public func write(_ amount: Double, for metric: GoalMetric, at date: Date) async throws {
        guard metric.isWritable else { throw HealthKitGoalError.writeNotPermitted(metric) }
        guard let type = metric.quantityType else { throw HealthKitGoalError.unsupportedMetric(metric) }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: metric.preferredUnit, doubleValue: amount),
            start: date,
            end: date
        )
        do {
            try await store.save(sample)
        } catch {
            throw HealthKitGoalError.wrapping(error)
        }
    }

    public func observe(
        _ metrics: Set<GoalMetric>,
        onChange: @escaping @Sendable () -> Void
    ) async throws -> HealthObservationToken {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitGoalError.healthDataUnavailable
        }
        var types: Set<HKSampleType> = []
        for metric in metrics {
            guard let type = metric.quantityType else { continue }
            types.insert(type)
            if metric.readsWorkouts {
                types.insert(HKObjectType.workoutType())
            }
        }
        guard !types.isEmpty else {
            return HealthObservationToken {}
        }

        var queries: [HKQuery] = []
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if let error {
                    Log.queries.error("Observer de \(type.identifier, privacy: .public) falhou: \(error.localizedDescription, privacy: .public)")
                } else {
                    onChange()
                }
                completion()
            }
            store.execute(query)
            queries.append(query)
        }

        let box = UncheckedBox((store: store, queries: queries))
        return HealthObservationToken {
            for query in box.value.queries {
                box.value.store.stop(query)
            }
        }
    }

    public func setBackgroundDelivery(enabled: Bool, for metrics: Set<GoalMetric>) async throws {
        #if os(iOS)
        for metric in metrics {
            guard let type = metric.quantityType else { continue }
            do {
                if enabled {
                    try await enableBackgroundDelivery(for: type)
                } else {
                    try await disableBackgroundDelivery(for: type)
                }
            } catch {
                Log.queries.error("Background delivery \(enabled ? "ligar" : "desligar", privacy: .public) falhou para \(metric.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        #else
        _ = (enabled, metrics)
        #endif
    }

    #if os(iOS)
    private func enableBackgroundDelivery(for type: HKQuantityType) async throws {
        let box = UncheckedBox((store: store, type: type))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            box.value.store.enableBackgroundDelivery(for: box.value.type, frequency: .hourly) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func disableBackgroundDelivery(for type: HKQuantityType) async throws {
        let box = UncheckedBox((store: store, type: type))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            box.value.store.disableBackgroundDelivery(for: box.value.type) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    #endif
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

#else

public final class LiveHealthStore: HealthStoreProviding, @unchecked Sendable {
    public init() {}

    public var isHealthDataAvailable: Bool {
        get async { false }
    }

    public func requestAuthorization(read: Set<GoalMetric>, write: Set<GoalMetric>) async throws {
        throw HealthKitGoalError.healthDataUnavailable
    }

    public func writeAuthorizationStatus(for metric: GoalMetric) async -> MetricAuthorization {
        .notRequested
    }

    public func total(for metric: GoalMetric, from start: Date, to end: Date) async throws -> Double? {
        nil
    }

    public func write(_ amount: Double, for metric: GoalMetric, at date: Date) async throws {
        throw HealthKitGoalError.healthDataUnavailable
    }

    public func observe(
        _ metrics: Set<GoalMetric>,
        onChange: @escaping @Sendable () -> Void
    ) async throws -> HealthObservationToken {
        HealthObservationToken {}
    }

    public func setBackgroundDelivery(enabled: Bool, for metrics: Set<GoalMetric>) async throws {}
}

#endif
