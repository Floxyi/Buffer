import AppKit
import SwiftUI

struct SettingsGeneralLaunchAtLoginSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Launch at Login") {
            Toggle("Open Buffer when you sign in", isOn: bindings.launchAtLogin)

            Text("Keep clipboard history running automatically in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsGeneralMenuBarSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Menu Bar") {
            Picker("Menu Bar Icon", selection: bindings.menuBarIcon) {
                ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                    Label(icon.label, systemImage: icon.symbolName)
                        .tag(icon)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct SettingsGeneralAppearanceSection: View {
    @ObservedObject var settings: SettingsManager

    private var bindings: SettingsFormBindings { settings.formBindings }

    var body: some View {
        Section("Appearance") {
            HStack(alignment: .top, spacing: 10) {
                ForEach(HistoryWindowMaterial.allCases, id: \.self) { material in
                    SettingsHistoryWindowMaterialOption(
                        material: material,
                        selection: bindings.historyWindowMaterial
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("History Window Material")

            Text("Choose between native Liquid Glass and the darker classic frosted appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsHistoryWindowMaterialOption: View {
    let material: HistoryWindowMaterial
    @Binding var selection: HistoryWindowMaterial

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool {
        selection == material
    }

    var body: some View {
        Button {
            selection = material
        } label: {
            VStack(spacing: 5) {
                materialPreview
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.28),
                                lineWidth: isSelected ? 3 : 1
                            )
                    }

                Text(material.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(material.label)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isSelected
        )
    }

    private var materialPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))

            previewSurface
                .frame(height: 24)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch material {
        case .liquidGlass:
            Color.clear
                .bufferGlassSurface(cornerRadius: 12)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                }
                .clipShape(Capsule())
        case .classic:
            Capsule()
                .fill(.regularMaterial)
                .background(Color.black.opacity(0.18), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.black.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
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
    let onRestoreLayout: () -> Void
    let onRestoreSettings: () -> Void

    var body: some View {
        Section {
            EmptyView()
        } footer: {
            HStack(spacing: 8) {
                Spacer()

                Button("Restore Default Layout", action: onRestoreLayout)
                    .buttonStyle(.bordered)

                Button(
                    "Restore Default Settings",
                    role: .destructive,
                    action: onRestoreSettings
                )
            }
            .padding(.top, 10)
        }
    }
}
