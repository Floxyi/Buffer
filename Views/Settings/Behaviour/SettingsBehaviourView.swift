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
            SettingsBehaviourItemActionsSection(settings: settings)
            SettingsBehaviourImageTextSection(settings: settings)
            SettingsBehaviourQuickPasteSection(settings: settings)
            SettingsBehaviourWhitespaceSection(settings: settings)
            SettingsBehaviourTextDetailSection(settings: settings, previewFont: previewFont)
        }
        .formStyle(.grouped)
    }
}
