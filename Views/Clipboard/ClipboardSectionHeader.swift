import SwiftUI

struct ClipboardSectionHeader: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
