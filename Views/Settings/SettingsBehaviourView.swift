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
            Section("History Window") {
                Toggle(
                    "Select the first non-pinned item on open",
                    isOn: Binding(
                        get: { settings.preferInitialSelectionFromFirstNonPinnedItem },
                        set: { settings.setPreferInitialSelectionFromFirstNonPinnedItem($0) }
                    )
                )
                Text("When off, Buffer keeps the current behavior and selects the first item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .formStyle(.grouped)
    }
}
