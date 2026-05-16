import AppKit
import SwiftUI

struct SettingsGeneralLaunchAtLoginSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Section("Launch at Login") {
            Toggle(
                "Open Buffer when you sign in",
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.toggleLaunchAtLogin($0) }
                )
            )

            Text("Keep clipboard history running automatically in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsGeneralMenuBarSection: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Section("Menu Bar") {
            Picker(
                "Menu Bar Icon",
                selection: Binding(
                    get: { settings.menuBarIcon },
                    set: { settings.setMenuBarIcon($0) }
                )
            ) {
                ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                    Label(icon.label, systemImage: icon.symbolName)
                        .tag(icon)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct SettingsGeneralHistorySizeSection: View {
    @Binding var draftHistoryLimitText: String
    var focusedField: FocusState<SettingsGeneralField?>.Binding
    let canApply: Bool
    let onSubmit: () -> Void

    var body: some View {
        Section("History Size") {
            HStack(alignment: .center, spacing: 12) {
                Text("Saved History")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    TextField("", text: $draftHistoryLimitText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .multilineTextAlignment(.trailing)
                        .focused(focusedField, equals: .historyLimit)
                        .onSubmit {
                            guard canApply else { return }
                            onSubmit()
                        }

                    Button("Apply", action: onSubmit)
                        .buttonStyle(.bordered)
                        .disabled(!canApply)
                }
            }
        }
    }
}

struct SettingsGeneralKeyboardShortcutSection: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isRecording: Bool

    var body: some View {
        Section("Keyboard Shortcut") {
            HStack(spacing: 12) {
                shortcutPreview

                Button(isRecording ? "Cancel" : "Change") {
                    isRecording.toggle()
                }

                Spacer()

                Button("Restore") {
                    settings.restoreDefaultHotkey()
                    isRecording = false
                }
            }

            Text(
                isRecording
                    ? "Press your new shortcut... (use at least one modifier key)"
                    : "Keyboard Shortcut to open clipboard history."
            )
            .font(.caption)
            .foregroundStyle(isRecording ? Color.accentColor : .secondary)
        }
    }

    private var shortcutPreview: some View {
        HStack(spacing: 4) {
            Text(settings.hotkeyModifiers.displayString)
            Text(AppFormatting.keyDisplayName(for: settings.hotkeyKeyCode))
        }
        .font(.system(.body).weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isRecording
                        ? Color.accentColor.opacity(0.15)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

struct SettingsGeneralRestoreDefaultsSection: View {
    let onRestore: () -> Void

    var body: some View {
        Section {
            EmptyView()
        } footer: {
            HStack {
                Spacer()

                Button("Restore Default Settings", role: .destructive, action: onRestore)
            }
            .padding(.top, 10)
        }
    }
}
