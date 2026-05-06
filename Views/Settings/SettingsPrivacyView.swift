import SwiftUI

struct SettingsPrivacyView: View {
    @ObservedObject var settings: SettingsManager
    let onPickExcludedApp: () -> Void

    var body: some View {
        Form {
            Section("Excluded Apps") {
                Text("Buffer will ignore copied text and images from these apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    if settings.excludedApps.isEmpty {
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
                    } else {
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
        }
        .formStyle(.grouped)
    }
}
