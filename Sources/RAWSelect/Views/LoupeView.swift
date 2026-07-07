import SwiftUI

/// Large preview of the selected photo with a filmstrip below.
struct LoupeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let group = app.currentGroup {
                LargePreview(group: group)
                    .id(group.id)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
            Divider()
            Filmstrip()
                .frame(height: 116)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LargePreview: View {
    @EnvironmentObject var app: AppState
    let group: PhotoGroup
    @State private var image: NSImage?
    @State private var metadata = PhotoMetadata()

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor).opacity(0.4)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                ProgressView()
            }

            VStack {
                HStack(alignment: .top) {
                    if app.showInfo { infoOverlay }
                    Spacer()
                    if group.mark != 0 { markPill }
                }
                Spacer()
                rejectBar
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sharp preview rendered from the full image at a fixed target size, so
        // prefetched neighbours share the same cache key and appear instantly.
        .task(id: group.id) {
            image = await ThumbnailLoader.shared.thumbnail(for: group.previewURL,
                                                           maxPixel: PreviewConfig.loupeMaxPixel,
                                                           fullQuality: true)
        }
        .task(id: group.id) {
            let url = group.files.first ?? group.previewURL
            metadata = await Task.detached { MetadataService.metadata(for: url) }.value
        }
    }

    private var markPill: some View {
        HStack(spacing: 6) {
            Circle().fill(MarkStyle.color(for: group.mark)).frame(width: 12, height: 12)
            Text("Markierung \(group.mark)").font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.displayName).font(.callout.weight(.semibold))
            Divider().padding(.vertical, 2)
            ForEach(metadata.rows, id: \.0) { row in
                HStack(spacing: 8) {
                    Text(row.0).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                    Text(row.1)
                }
                .font(.caption.monospacedDigit())
            }
            if metadata.rows.isEmpty {
                Text("Keine EXIF-Daten").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 280, alignment: .leading)
    }

    @ViewBuilder
    private var rejectBar: some View {
        Button {
            app.toggleReject()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: group.reject ? "xmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(group.reject ? .red : .secondary)
                Text(group.reject ? "Ausschuss" : "Als Ausschuss markieren")
                    .font(.callout)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct Filmstrip: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.filteredGroups) { group in
                        ThumbnailCell(group: group,
                                      isSelected: app.selectedIDs.contains(group.id),
                                      isCurrent: group.id == app.currentID,
                                      side: 84, showsCaption: false)
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture { app.click(group.id) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .onChange(of: app.currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
