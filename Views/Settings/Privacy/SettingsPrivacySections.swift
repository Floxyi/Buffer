import AppKit
import SwiftUI

struct SettingsPrivacyWebsitePreviewsSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Section("Website Data") {
            Toggle(
                "Enable Website Previews and Icons",
                isOn: Binding(
                    get: { settings.enableWebsitePreviews },
                    set: { settings.setEnableWebsitePreviews($0) }
                )
            )

            Text("When enabled, Buffer may fetch website metadata and favicons for link items. Disable this to keep link handling fully local-only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsPrivacyAutoClearHistorySection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
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
    }
}

struct SettingsPrivacyExcludedAppsSection: View {
    @ObservedObject var settings: SettingsManager
    let onPickExcludedApp: () -> Void
    @State private var iconRefreshToken = 0

    var body: some View {
        Section("Excluded Apps") {
            Text("Buffer will ignore copied text and images from these apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                if settings.excludedApps.isEmpty {
                    SettingsPrivacyEmptyExcludedAppsView()
                } else {
                    SettingsPrivacyExcludedAppsList(
                        settings: settings,
                        iconRefreshToken: iconRefreshToken
                    )
                }
            }
            .frame(height: 220)

            HStack {
                Spacer()

                Button(action: onPickExcludedApp) {
                    Image(systemName: "plus")
                }
                .help("Add App")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            iconRefreshToken &+= 1
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
            iconRefreshToken &+= 1
        }
    }
}

struct SettingsPrivacyEmptyExcludedAppsView: View {
    var body: some View {
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
}

struct SettingsPrivacyExcludedAppsList: View {
    @ObservedObject var settings: SettingsManager
    let iconRefreshToken: Int

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(settings.excludedApps) { app in
                SettingsPrivacyExcludedAppRow(app: app, iconRefreshToken: iconRefreshToken) {
                    settings.removeExcludedApp(app)
                }

                if app.id != settings.excludedApps.last?.id {
                    Divider()
                }
            }
        }
    }
}

struct SettingsPrivacyExcludedAppRow: View {
    let app: ExcludedApp
    let iconRefreshToken: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsPrivacyAppIconView(
                bundlePath: app.bundlePath,
                refreshToken: iconRefreshToken
            )
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

private struct SettingsPrivacyAppIconView: NSViewRepresentable {
    let bundlePath: String
    let refreshToken: Int

    func makeNSView(context: Context) -> IconImageView {
        let imageView = IconImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.bundlePath = bundlePath
        return imageView
    }

    func updateNSView(_ nsView: IconImageView, context: Context) {
        nsView.bundlePath = bundlePath
        nsView.refreshIcon()
    }

    final class IconImageView: NSImageView {
        var bundlePath = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshIcon()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshIcon()
        }

        func refreshIcon() {
            guard !bundlePath.isEmpty else {
                image = nil
                return
            }

            let appearance = effectiveAppearance
            var resolvedIcon: NSImage?
            appearance.performAsCurrentDrawingAppearance {
                resolvedIcon = NSWorkspace.shared.icon(forFile: bundlePath)
            }

            let iconCopy = resolvedIcon?.copy() as? NSImage ?? resolvedIcon
            iconCopy?.size = NSSize(width: 28, height: 28)
            image = nil
            image = iconCopy
            needsDisplay = true
        }
    }
}
