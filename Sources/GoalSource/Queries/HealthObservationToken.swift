import Foundation

public final class HealthObservationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    public init(onCancel: @escaping @Sendable () -> Void) {
        cancelHandler = onCancel
    }

    public func cancel() {
        lock.lock()
        let handler = cancelHandler
        cancelHandler = nil
        lock.unlock()
        handler?()
    }

    deinit {
        cancel()
    }
}
