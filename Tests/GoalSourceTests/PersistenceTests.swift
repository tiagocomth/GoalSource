import XCTest
@testable import GoalSource

final class PersistenceTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shared-goals-tests-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    func testFileStoreReturnsEmptyStateBeforeAnythingIsWritten() async throws {
        let state = try await FileSnapshotStore(fileURL: fileURL).load()
        XCTAssertEqual(state, PersistedState())
    }

    func testFileStoreRestoresWhatItSaved() async throws {
        let goalID = "goal-1"
        let snapshot = DailySnapshot(
            date: Fixture.noon,
            progress: [GoalProgress(goalID: goalID, value: 3, target: 4, lastUpdated: Fixture.noon)]
        )
        var state = PersistedState()
        state.lastSnapshot = snapshot
        state.requestedMetrics = [.water, .stepCount]

        try await FileSnapshotStore(fileURL: fileURL).save(state)

        let restored = try await FileSnapshotStore(fileURL: fileURL).load()
        XCTAssertEqual(restored.requestedMetrics, [.water, .stepCount])
        XCTAssertEqual(restored.lastSnapshot, snapshot)
    }

    func testFileStoreCreatesMissingDirectories() async throws {
        try await FileSnapshotStore(fileURL: fileURL).save(PersistedState(requestedMetrics: [.water]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptCacheDoesNotFailTheLaunch() async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: fileURL)

        let state = try await FileSnapshotStore(fileURL: fileURL).load()
        XCTAssertEqual(state, PersistedState(), "A broken cache starts empty instead of throwing.")
    }
}
