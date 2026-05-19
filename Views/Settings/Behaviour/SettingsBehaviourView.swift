import SwiftUI

struct SettingsBehaviourView: View {
    @ObservedObject var settings: SettingsManager

    private var previewFont: Font {
        let size = CGFloat(settings.textDetailFontSize.rawValue)
        switch settings.textDetailFontStyle {
        case .regular:
            return .system(size: size)
        case .monospaced:
            return .system(size: size, design: .monospaced)
        }
    }

    var body: some View {
        Form {
            SettingsBehaviourHistoryWindowSection(settings: settings)
            SettingsBehaviourSearchSection(settings: settings)
            SettingsBehaviourQuickPasteSection(settings: settings)
            SettingsBehaviourTextDetailSection(settings: settings, previewFont: previewFont)
        }
        .formStyle(.grouped)
    }
}
