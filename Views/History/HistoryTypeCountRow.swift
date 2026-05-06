import SwiftUI

struct HistoryTypeCountRow: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12))
        }
    }
}
