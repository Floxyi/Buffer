import SwiftUI

struct ClipboardQuickPasteBadge: View {
    let number: Int
    let foregroundColor: Color
    let isMultiSelected: Bool

    var body: some View {
        Text("⌘\(number)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(foregroundColor)
            .frame(minWidth: 28, minHeight: 20)
            .padding(.horizontal, 2)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(isMultiSelected ? 0.18 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isMultiSelected ? 0.22 : 0.12), lineWidth: 0.5)
            )
    }
}
