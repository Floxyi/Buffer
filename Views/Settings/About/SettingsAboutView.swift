import AppKit
import SwiftUI

struct SettingsAboutView: View {
    let about: AppMetadata

    var body: some View {
        Form {
            SettingsAboutHeaderSection(about: about)
            SettingsAboutLicenseSection(about: about)
        }
        .formStyle(.grouped)
    }
}
