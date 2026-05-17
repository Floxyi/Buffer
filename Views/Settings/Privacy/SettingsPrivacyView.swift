import AppKit
import SwiftUI

struct SettingsPrivacyView: View {
    @ObservedObject var settings: SettingsManager
    @State private var pickerDelegate: AppBundleOpenPanelDelegate?

    var body: some View {
        Form {
            SettingsPrivacyWebsitePreviewsSection(settings: settings)
            SettingsPrivacyAutoClearHistorySection(settings: settings)
            SettingsPrivacyExcludedAppsSection(
                settings: settings,
                onPickExcludedApp: pickExcludedApp
            )
        }
        .formStyle(.grouped)
    }

    private func pickExcludedApp() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        panel.message = "Select an app whose copied content Buffer should ignore."

        let delegate = AppBundleOpenPanelDelegate()
        pickerDelegate = delegate
        panel.delegate = delegate

        panel.beginSheetModal(for: window) { response in
            defer {
                pickerDelegate = nil
            }

            guard response == .OK, let url = panel.url else {
                return
            }

            guard let app = ExcludedApp(url: url) else {
                return
            }

            settings.addExcludedApp(app)
        }
    }
}
