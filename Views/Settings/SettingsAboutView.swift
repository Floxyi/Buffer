import AppKit
import SwiftUI

struct SettingsAboutView: View {
    let about: AppMetadata

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(about.name)
                            .font(.title3.weight(.semibold))
                        Text("Version \(about.version) (\(about.build))")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check for Updates") {
                    }
                    .padding(.trailing, 6)
                }
            }

            Section("License") {
                ScrollView {
                    Text(about.licenseText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(height: 300)
            }
        }
        .formStyle(.grouped)
    }
}
