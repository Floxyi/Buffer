import SwiftUI

struct HistorySearchBar: View {
    @Binding var searchText: String
    let filteredItemCount: Int
    let isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.82))
                .font(.system(size: 18, weight: .medium))
                .frame(width: 18, height: 24)
                .padding(.leading, 2)

            HStack(alignment: .center, spacing: 10) {
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused(isSearchFocused)
                    .frame(height: 24, alignment: .center)
                    .lineLimit(1)

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
                .frame(height: 24, alignment: .center)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .frame(height: 52, alignment: .center)
    }
}
