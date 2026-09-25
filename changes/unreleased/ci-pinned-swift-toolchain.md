CI installs the Swift 6.3.3 toolchain on Linux from swift.org through a local
action that checks a pinned SHA-256, replacing swift-actions/setup-swift, whose
Swiftly bootstrap began failing GPG verification on hosted runners (#36).
