import EnginePorts
import Foundation

public actor RecordingNotifier: UserNotifier {
    public enum Failure: Error, Equatable {
        case injected(attempt: Int)
    }

    public private(set) var notices: [UserNotice] = []
    public private(set) var attempts = 0
    private let failOnAttempt: Int?

    /// `failOnAttempt` is 1-based: pass 2 to fail the second `notify`.
    public init(failOnAttempt: Int? = nil) {
        self.failOnAttempt = failOnAttempt
    }

    public var kinds: [UserNotice.Kind] {
        notices.map(\.kind)
    }

    public func notify(_ notice: UserNotice) async throws {
        attempts += 1
        if attempts == failOnAttempt {
            throw Failure.injected(attempt: attempts)
        }
        notices.append(notice)
    }
}
