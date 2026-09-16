// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What to call the device the person is holding.
///
/// The same binary runs on iPhone and iPad, and copy that says "this iPhone" on
/// an iPad is wrong in the one place a user checks when they are deciding whether
/// to trust where their health data goes. It is also wrong about which device it
/// is describing: an iPad reads its own Health store, not the phone's.
///
/// The app sets this once at launch, because the alternative is threading an
/// idiom flag through every piece of copy in the product. It is deliberately a
/// noun and nothing more: nothing branches on it, so it cannot become a second
/// way of asking what device this is. `HealthAvailability.isVisible(idiomIsPad:)`
/// remains how behaviour is decided.
public enum DeviceNoun: Sendable {
    /// The default is the phone, which is what the overwhelming majority of
    /// installs are, and what every string said before this existed.
    private static let state = Storage()

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var isPad = false

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return isPad
            }
            set {
                lock.lock()
                isPad = newValue
                lock.unlock()
            }
        }
    }

    /// Set once, at launch, from the running device's interface idiom.
    public static func configure(idiomIsPad: Bool) {
        state.value = idiomIsPad
    }

    /// "iPhone" or "iPad". Capitalised, because it is a product name in both
    /// cases and appears mid-sentence.
    public static var current: String {
        state.value ? "iPad" : "iPhone"
    }

    /// "this iPhone" / "this iPad", the form most of the copy needs.
    public static var thisDevice: String {
        "this \(current)"
    }

    /// "The iPhone" / "The iPad", for the start of a sentence.
    public static var theDevice: String {
        "The \(current)"
    }
}
