import Foundation
import Observation

@MainActor
@Observable
public final class GoalsMonitor {
    public private(set) var goals: [GoalDefinition]

    public private(set) var snapshot: DailySnapshot?

    public private(set) var authorization: AuthorizationSummary?

    public private(set) var lastError: HealthKitGoalError?

    public private(set) var isLoading = false

    @ObservationIgnored private let store: HealthKitGoalStore

    public init(goals: [GoalDefinition], store: HealthKitGoalStore) {
        self.goals = goals
        self.store = store
    }

    public static func preview(
        goals: [GoalDefinition],
        totals: [GoalMetric: Double] = [:]
    ) -> GoalsMonitor {
        GoalsMonitor(goals: goals, store: .preview(totals: totals))
    }

    public func start(requestingAuthorization: Bool = true) async {
        isLoading = snapshot == nil
        snapshot = await store.cachedSnapshot() ?? snapshot
        authorization = await store.authorizationStatus(for: goals)

        if requestingAuthorization, authorization?.needsPrompt == true {
            await requestAuthorization()
        }

        for await snapshot in await store.liveSnapshots(for: goals) {
            self.snapshot = snapshot
            self.isLoading = false
            self.lastError = nil
        }
        isLoading = false
    }

    public func setGoals(_ goals: [GoalDefinition]) {
        self.goals = goals
        snapshot = nil
    }

    public func requestAuthorization() async {
        do {
            try await store.requestAuthorization(for: goals)
            lastError = nil
        } catch {
            lastError = .wrapping(error)
        }
        authorization = await store.authorizationStatus(for: goals)
    }

    public func refresh() async {
        isLoading = snapshot == nil
        do {
            snapshot = try await store.snapshot(for: goals, on: Date())
            lastError = nil
        } catch {
            lastError = .wrapping(error)
        }
        isLoading = false
    }

    public func log(_ amount: Double, for metric: GoalMetric, at date: Date = Date()) async {
        do {
            try await store.log(amount, for: metric, at: date)
            lastError = nil
        } catch {
            lastError = .wrapping(error)
        }
    }

    public var overallFraction: Double {
        snapshot?.overallFraction ?? 0
    }

    public var isDayComplete: Bool {
        snapshot?.isComplete ?? false
    }

    public func progress(for goal: GoalDefinition) -> GoalProgress? {
        snapshot?.progress(for: goal.id)
    }

    public func fraction(for goal: GoalDefinition) -> Double {
        progress(for: goal)?.fraction ?? 0
    }

    public func isComplete(_ goal: GoalDefinition) -> Bool {
        progress(for: goal)?.isComplete ?? false
    }

    public func needsHealthAccess(for goal: GoalDefinition) -> Bool {
        switch progress(for: goal)?.unavailableReason {
        case .authorizationNotRequested, .authorizationDenied: true
        case .noSamples, .metricUnavailableOnDevice, nil: false
        }
    }
}
