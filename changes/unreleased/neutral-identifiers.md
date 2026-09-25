Every bundle-scoped identifier derives from one neutral root, `com.cewdesign.exporter`,
set only in Brand.xcconfig: bundle IDs, the App Group, background tasks, the URL
scheme, keychain services, queue labels and the log subsystem. Credentials saved by
earlier pre-release builds under the old keychain services are not carried over. A
weekly rename drill proves no build hard-codes the root elsewhere (#35).
