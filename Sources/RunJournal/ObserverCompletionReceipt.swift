// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// HK-11: an observer completion receipt is consumed at most once on every callback path.
public final class ObserverCompletionReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?

    public init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    public func finish() {
        let callback: (() -> Void)?
        lock.lock()
        callback = completion
        completion = nil
        lock.unlock()
        callback?()
    }

    deinit {
        finish()
    }
}
