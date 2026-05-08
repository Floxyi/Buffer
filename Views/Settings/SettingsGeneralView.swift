import AppKit
import SwiftUI

struct SettingsGeneralView: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isRecording: Bool
    @Binding var showingTrimAlert: Bool
    @Binding var pendingTier: HistoryLimit?

    @State private var showingResetAlert = false

    var body: some View {
        Form {
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

            Section("History Size") {
                Picker("Saved History", selection: $settings.historyLimit) {
                    ForEach(HistoryLimit.allCases, id: \.self) { tier in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.label)
                            Text(tier.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(tier)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.historyLimit) { newValue in
                    guard newValue != settings.persistedHistoryLimit else { return }

                    if newValue.rawValue < settings.persistedHistoryLimit.rawValue {
                        pendingTier = newValue
                        settings.historyLimit = settings.persistedHistoryLimit
                        showingTrimAlert = true
                    } else {
                        settings.setHistoryLimit(newValue)
                    }
                }
            }

            Section("Keyboard Shortcut") {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(settings.hotkeyModifiers.displayString)
                        Text(AppFormatting.keyDisplayName(for: settings.hotkeyKeyCode))
                    }
                    .font(.system(.body).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )

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

            Section {
                EmptyView()
            } footer: {
                HStack {
                    Spacer()

                    Button("Restore Default Settings", role: .destructive) {
                        showingResetAlert = true
                    }
                }
                .padding(.top, 10)
            }
        }
        .formStyle(.grouped)
        .alert("Restore Default Settings?", isPresented: $showingResetAlert) {
            Button("Restore Defaults", role: .destructive) {
                settings.resetUserPreferencesToDefaults()
                isRecording = false
                pendingTier = nil
                showingTrimAlert = false
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your preferences to their default values. Your clipboard history and excluded apps will not be deleted.")
        }
    }
}
