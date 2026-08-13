import SwiftUI

struct SettingsBehaviourHistoryWindowSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("History Window") {
            Picker("Reopen behavior", selection: bindings.historyWindowOpenBehavior) {
                ForEach(HistoryWindowOpenBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.label).tag(behavior)
                }
            }

            Text(
                "Choose whether Buffer restores the previous selection or selects a fresh item when the history window reopens."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourSearchSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Search Behaviour") {
            Toggle("Keep the search text after pasting", isOn: bindings.searchBehavior.keepSearchTextAfterPaste)

            Toggle("Keep the search text after closing", isOn: bindings.searchBehavior.keepSearchTextAfterClosing)

            Text(
                "Choose whether the search field is preserved after pasting or copying an item, and after closing the history window."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourItemActionsSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Item Actions") {
            Toggle(
                "Confirm before deleting with keyboard shortcut",
                isOn: bindings.searchBehavior.confirmDeleteWithKeyboardShortcut)

            Text("Choose whether Delete or Command-Delete asks for confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourQuickPasteSection: View {
    @ObservedObject var settings: SettingsManager

    private let entryCountOptions = Array(SettingsDefaults.quickPasteEntryCountRange)
    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Quick Paste Shortcuts") {
            Toggle("Enable Command-number quick paste", isOn: bindings.quickPaste.enabled)

            Picker("Start numbers at", selection: bindings.quickPaste.numberingStart) {
                ForEach(QuickPasteNumberingStart.allCases, id: \.self) { start in
                    Text(start.label).tag(start)
                }
            }
            .disabled(!settings.quickPasteEnabled)

            Picker("Addressable entries", selection: bindings.quickPaste.entryCount) {
                ForEach(entryCountOptions, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .disabled(!settings.quickPasteEnabled)

            Text(
                "Choose whether Command-number quick paste starts in the pinned section or at the first normal history item, and how many entries it can address."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourWhitespaceSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Whitespace") {
            Toggle(
                "Show spaces and tabs in text details",
                isOn: bindings.whitespace.showSpacesAndTabs
            )
            .disabled(settings.clipboardWhitespaceMode.trimsTrailingSpacesAndTabs)

            Toggle(
                "Remove trailing spaces and tabs from copied text",
                isOn: bindings.whitespace.trimTrailingSpacesAndTabs
            )
            .disabled(settings.clipboardWhitespaceMode.showsSpacesAndTabs)

            Text(
                "Visible whitespace changes only Buffer's text detail display. Trimming applies only to new history entries and leaves the system clipboard unchanged."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SettingsBehaviourTextDetailSection: View {
    @ObservedObject var settings: SettingsManager
    let previewFont: Font

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Text Detail View") {
            Picker("Text Size", selection: bindings.textDetail.fontSize) {
                ForEach(TextDetailFontSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }

            Picker("Font", selection: bindings.textDetail.fontStyle) {
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
