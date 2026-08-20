import Foundation

public extension HealthKitGoalStore {
    struct Configuration: Sendable {
        public var debounceInterval: Duration

        public var enablesBackgroundDelivery: Bool

        public var calendar: Calendar

        public var snapshotStore: any SnapshotStoring

        public init(
            debounceInterval: Duration = .seconds(2),
            enablesBackgroundDelivery: Bool = false,
            calendar: Calendar = .autoupdatingCurrent,
            snapshotStore: any SnapshotStoring = FileSnapshotStore.default
        ) {
            self.debounceInterval = debounceInterval
            self.enablesBackgroundDelivery = enablesBackgroundDelivery
            self.calendar = calendar
            self.snapshotStore = snapshotStore
        }

        public static let `default` = Configuration()

        public static func appGroup(
            _ identifier: String,
            backgroundDelivery: Bool = true
        ) -> Configuration {
            Configuration(
                enablesBackgroundDelivery: backgroundDelivery,
                snapshotStore: FileSnapshotStore(appGroupIdentifier: identifier)
            )
        }
    }
}
