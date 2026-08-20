import Foundation

public protocol SnapshotStoring: Sendable {
    func load() async throws -> PersistedState
    func save(_ state: PersistedState) async throws
}

public actor InMemorySnapshotStore: SnapshotStoring {
    private var state: PersistedState

    public init(state: PersistedState = PersistedState()) {
        self.state = state
    }

    public func load() async throws -> PersistedState { state }

    public func save(_ state: PersistedState) async throws { self.state = state }
}
