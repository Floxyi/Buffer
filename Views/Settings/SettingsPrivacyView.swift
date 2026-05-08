import AppKit
import SwiftUI

struct SettingsPrivacyView: View {
    @ObservedObject var settings: SettingsManager

    @State private var pickerDelegate: AppBundleOpenPanelDelegate?

    var body: some View {
        Form {
            Section("Auto-Clear History") {
                Picker(
                    "Clear History Entries",
                    selection: Binding(
                        get: { settings.historyRetentionPeriod },
                        set: { settings.setHistoryRetentionPeriod($0) }
                    )
                ) {
                    ForEach(HistoryRetentionPeriod.allCases, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }

                Text("Automatically removes history entries older than the selected age.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded Apps") {
                Text("Buffer will ignore copied text and images from these apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    if settings.excludedApps.isEmpty {
                        emptyExcludedAppsView
                    } else {
                        excludedAppsList
                    }
                }
                .frame(height: 220)

                HStack {
                    Spacer()

                    Button {
                        pickExcludedApp()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add App")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var emptyExcludedAppsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text("No Excluded Apps")
                .font(.headline)

            Text("Add apps like password managers to keep their copied content out of Buffer history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var excludedAppsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(settings.excludedApps) { app in
                ExcludedAppRow(app: app) {
                    settings.removeExcludedApp(app)
                }

                if app.id != settings.excludedApps.last?.id {
                    Divider()
                }
            }
        }
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

private struct ExcludedAppRow: View {
    let app: ExcludedApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)

                Text(app.bundleIdentifier ?? app.bundlePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Remove app")
        }
        .padding(.vertical, 8)
    }
}
