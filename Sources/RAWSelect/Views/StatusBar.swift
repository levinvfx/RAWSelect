import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 12) {
            if app.isScanning {
                ProgressView().controlSize(.small)
            }
            Text(app.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let group = app.selectedGroup {
                Text(group.displayName)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !app.filteredGroups.isEmpty {
                Text(positionText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.bar)
    }

    private var positionText: String {
        let list = app.filteredGroups
        if let id = app.selectedID, let idx = list.firstIndex(where: { $0.id == id }) {
            return "\(idx + 1) / \(list.count)"
        }
        return "\(list.count)"
    }
}
