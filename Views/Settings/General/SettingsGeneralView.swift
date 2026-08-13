import AppKit
import SwiftUI

enum SettingsGeneralField: Hashable {
    case historyLimit
}

struct SettingsGeneralView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var store: ClipboardStore

    @State private var isRecording = false
    @State private var showingTrimAlert = false
    @State private var pendingHistoryLimit: Int?
    @State private var pendingDeletionCount = 0
    @State private var draftHistoryLimitText: String
    @State private var showingResetAlert = false
    @FocusState private var focusedField: SettingsGeneralField?

    init(settings: SettingsManager, store: ClipboardStore) {
        self._settings = ObservedObject(wrappedValue: settings)
        self._store = ObservedObject(wrappedValue: store)
        self._draftHistoryLimitText = State(initialValue: String(settings.persistedHistoryLimit))
    }

    var body: some View {
        Form {
            SettingsGeneralLaunchAtLoginSection(settings: settings)
            SettingsGeneralMenuBarSection(settings: settings)
            SettingsGeneralHistorySizeSection(
                draftHistoryLimitText: $draftHistoryLimitText,
                focusedField: $focusedField,
                canApply: canApplyHistoryLimit
            ) {
                applyDraftHistoryLimit()
            }
            SettingsGeneralKeyboardShortcutSection(
                settings: settings,
                isRecording: $isRecording
            )
            SettingsGeneralRestoreDefaultsSection {
                showingResetAlert = true
            }
        }
        .formStyle(.grouped)
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) {
                pendingHistoryLimit = nil
                pendingDeletionCount = 0
                draftHistoryLimitText = String(settings.persistedHistoryLimit)
            }

            Button("Reduce & Delete", role: .destructive) {
                if let limit = pendingHistoryLimit {
                    settings.setHistoryLimit(limit)
                    draftHistoryLimitText = String(limit)
                }

                pendingHistoryLimit = nil
                pendingDeletionCount = 0
            }
        } message: {
            Text(trimAlertMessage)
        }
        .alert("Restore Default Settings?", isPresented: $showingResetAlert) {
            Button("Restore Defaults", role: .destructive) {
                settings.resetUserPreferencesToDefaults()
                isRecording = false
                pendingHistoryLimit = nil
                pendingDeletionCount = 0
                draftHistoryLimitText = String(settings.persistedHistoryLimit)
                showingTrimAlert = false
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will reset your preferences to their default values. Your clipboard history and excluded apps will not be deleted."
            )
        }
        .background(
            KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
                settings.setHotkey(keyCode: keyCode, modifiers: modifiers)
                isRecording = false
            }
        )
        .onChange(of: settings.persistedHistoryLimit) { newValue in
            draftHistoryLimitText = String(newValue)
        }
    }

    private var canApplyHistoryLimit: Bool {
        guard let parsedLimit = parsedHistoryLimit else { return false }
        return SettingsDefaults.normalizedHistoryLimit(parsedLimit) != settings.persistedHistoryLimit
    }

    private var parsedHistoryLimit: Int? {
        guard let parsedLimit = Int(draftHistoryLimitText), parsedLimit > 0 else { return nil }
        return parsedLimit
    }

    private var trimAlertMessage: String {
        let entryDescription =
            pendingDeletionCount == 1
            ? String(localized: "1 clipboard item")
            : String(localized: "\(pendingDeletionCount) clipboard items")
        return String(
            localized:
                "This will permanently delete \(entryDescription) from your oldest unprotected history to fit the new size. This action cannot be undone."
        )
    }

    private func applyDraftHistoryLimit() {
        guard let parsedLimit = parsedHistoryLimit else { return }

        let normalizedLimit = SettingsDefaults.normalizedHistoryLimit(parsedLimit)
        if normalizedLimit != parsedLimit {
            draftHistoryLimitText = String(normalizedLimit)
        }

        applyHistoryLimitChange(normalizedLimit)
    }

    private func applyHistoryLimitChange(_ proposedLimit: Int) {
        guard proposedLimit != settings.persistedHistoryLimit else { return }

        let deletionCount = deletionCountIfReducing(to: proposedLimit)
        if proposedLimit < settings.persistedHistoryLimit, deletionCount > 0 {
            pendingHistoryLimit = proposedLimit
            pendingDeletionCount = deletionCount
            draftHistoryLimitText = String(settings.persistedHistoryLimit)
            showingTrimAlert = true
            return
        }

        settings.setHistoryLimit(proposedLimit)
        draftHistoryLimitText = String(proposedLimit)
    }

    private func deletionCountIfReducing(to proposedLimit: Int) -> Int {
        guard proposedLimit < settings.persistedHistoryLimit else { return 0 }

        let requiredRemovals = max(store.items.count - proposedLimit, 0)
        let removableItems = store.items.lazy.filter { !$0.isProtectedFromDeletion }.count
        return min(requiredRemovals, removableItems)
    }
}
