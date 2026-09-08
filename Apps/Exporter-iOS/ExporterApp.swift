import SwiftUI

@main
struct ExporterApp: App {
    @UIApplicationDelegateAdaptor(ExporterAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            HarnessView()
        }
    }
}
