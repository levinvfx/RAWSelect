import SwiftUI

struct StatusBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

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
                .layoutPriority(1)

            if app.viewMode == .grid && !app.groups.isEmpty {
                sizeSlider
            }

            Spacer(minLength: 12)

            if let group = app.currentGroup {
                if app.selectionCount > 1 {
                    Text("\(app.selectionCount) ausgewählt")
                        .foregroundStyle(Color.accentColor)
                }
                Text(sizeString(group.fileSize))
                    .foregroundStyle(.tertiary)
                Text(pathString(group))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
            if !app.filteredGroups.isEmpty {
                Text(positionText)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(.bar)
    }

    private var sizeSlider: some View {
        Picker("", selection: $settings.thumbnailSizeChoice) {
            Image(systemName: "square.grid.3x3").tag(ThumbnailSize.small)
            Image(systemName: "square.grid.2x2").tag(ThumbnailSize.medium)
            Image(systemName: "square").tag(ThumbnailSize.large)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 108)
        .help("Thumbnail-Grösse")
    }

    private func sizeString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func pathString(_ group: PhotoGroup) -> String {
        (group.files.first ?? group.previewURL).path
    }

    private var positionText: String {
        let list = app.filteredGroups
        if let id = app.currentID, let idx = list.firstIndex(where: { $0.id == id }) {
            return "\(idx + 1) / \(list.count)"
        }
        return "\(list.count)"
    }
}
