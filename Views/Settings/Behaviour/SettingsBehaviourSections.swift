import SwiftUI

struct SettingsBehaviourHistoryWindowSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Section("History Window") {
            Picker(
                "Reopen behavior",
                selection: Binding(
                    get: { settings.historyWindowOpenBehavior },
                    set: { settings.setHistoryWindowOpenBehavior($0) }
                )
            ) {
                ForEach(HistoryWindowOpenBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.label).tag(behavior)
                }
            }

            Text("Choose whether Buffer restores the previous list selection or opens from the top.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourPasteSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Section("Paste Behaviour") {
            Toggle(
                "Keep the search text after pasting",
                isOn: Binding(
                    get: { settings.keepSearchTextAfterPaste },
                    set: { settings.setKeepSearchTextAfterPaste($0) }
                )
            )

            Text("When off, the search field is cleared after you paste or copy an item from history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourTextDetailSection: View {
    @ObservedObject var settings: SettingsManager
    let previewFont: Font

    var body: some View {
        Section("Text Detail View") {
            Picker(
                "Text Size",
                selection: Binding(
                    get: { settings.textDetailFontSize },
                    set: { settings.setTextDetailFontSize($0) }
                )
            ) {
                ForEach(TextDetailFontSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }

            Picker(
                "Font",
                selection: Binding(
                    get: { settings.textDetailFontStyle },
                    set: { settings.setTextDetailFontStyle($0) }
                )
            ) {
                ForEach(TextDetailFontStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }

            Text("The quick brown fox jumps over 13 lazy dogs.")
                .font(previewFont)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
    }
}
