import Foundation

public actor FileSnapshotStore: SnapshotStoring {
    private let fileURL: URL
    private var cached: PersistedState?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(appGroupIdentifier: String?, filename: String = "goal-source-state.json") {
        self.fileURL = Self.containerURL(appGroupIdentifier: appGroupIdentifier)
            .appendingPathComponent(filename)
    }

    public static let `default` = FileSnapshotStore(appGroupIdentifier: nil)

    public func load() async throws -> PersistedState {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = PersistedState()
            cached = empty
            return empty
        }
        do {
            let state = try Self.decoder.decode(PersistedState.self, from: Data(contentsOf: fileURL))
            cached = state
            return state
        } catch {
            Log.persistence.error("Descartando cache ilegível em \(self.fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let empty = PersistedState()
            cached = empty
            return empty
        }
    }

    public func save(_ state: PersistedState) async throws {
        cached = state
        let data = try Self.encoder.encode(state)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func containerURL(appGroupIdentifier: String?) -> URL {
        if let appGroupIdentifier,
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            return container
        }
        if appGroupIdentifier != nil {
            Log.persistence.error("Container do App Group indisponível; os widgets não vão ver este cache.")
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return fallback ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
