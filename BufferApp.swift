import SwiftUI

@main
@MainActor
struct BufferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settingsManager)
        }
    }
}
