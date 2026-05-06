import AppKit
import SwiftUI

struct HistorySearchBar: View {
    @Binding var searchText: String
    let filteredItemCount: Int
    @Binding var isSearchFocused: Bool
    let searchSelectionToken: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.82))
                .font(.system(size: 18, weight: .medium))
                .frame(width: 18, height: 24)
                .padding(.leading, 2)

            HStack(alignment: .center, spacing: 10) {
                SearchFieldBridge(
                    text: $searchText,
                    isFocused: $isSearchFocused,
                    selectionToken: searchSelectionToken,
                    placeholder: "Search clipboard..."
                )
                .frame(height: 24, alignment: .center)

                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                        .font(.system(size: 14))
                        .frame(width: 16, height: 24)
                }
                .buttonStyle(.plain)
                .opacity(searchText.isEmpty ? 0 : 1)
                .disabled(searchText.isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .center)

            Text("\(filteredItemCount) items")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary.opacity(0.72))
                .frame(width: 80, height: 24, alignment: .trailing)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .frame(height: 52, alignment: .center)
    }
}

private struct SearchFieldBridge: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let selectionToken: Int
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> FocusableSearchTextField {
        let textField = FocusableSearchTextField(frame: .zero)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 18)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.focusChangeHandler = { isFocused in
            context.coordinator.handleFocusChange(isFocused)
        }
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ nsView: FocusableSearchTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if context.coordinator.pendingSelectionToken != selectionToken {
            context.coordinator.pendingSelectionToken = selectionToken
        }

        if isFocused {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }

                if window.firstResponder !== nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                }

                context.coordinator.applyPendingSelectionIfNeeded(to: nsView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        var pendingSelectionToken = 0
        private var appliedSelectionToken = -1

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            if text.wrappedValue != textField.stringValue {
                text.wrappedValue = textField.stringValue
            }
        }

        func handleFocusChange(_ isFocused: Bool) {
            self.isFocused.wrappedValue = isFocused
        }

        func applyPendingSelectionIfNeeded(to textField: NSTextField) {
            guard pendingSelectionToken != appliedSelectionToken else { return }
            guard let editor = textField.currentEditor() else { return }

            textField.selectText(nil)
            editor.selectedRange = NSRange(location: 0, length: editor.string.count)
            appliedSelectionToken = pendingSelectionToken
        }
    }
}

private final class FocusableSearchTextField: NSTextField {
    var focusChangeHandler: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            focusChangeHandler?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            focusChangeHandler?(false)
        }
        return didResignFirstResponder
    }
}
