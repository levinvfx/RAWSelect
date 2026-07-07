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
    let group: PhotoGroup
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            let target = Self.targetPixels(for: geo.size)
            ZStack {
                Color(nsColor: .textBackgroundColor).opacity(0.4)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                } else {
                    ProgressView("Vorschau wird geladen…")
                }

                if group.mark != 0 {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(MarkStyle.color(for: group.mark)).frame(width: 12, height: 12)
                                Text("Markierung \(group.mark)")
                                    .font(.callout.weight(.medium))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(16)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Sharp preview rendered from the full image, matched to the display's
            // pixel size (min Full HD). Only the currently viewed photo is decoded,
            // and results are cached; copying still reads the original bytes.
            .task(id: "\(group.id)|\(target)") {
                image = await ThumbnailLoader.shared.thumbnail(for: group.previewURL,
                                                               maxPixel: target, fullQuality: true)
            }
        }
    }

    /// Long-edge pixel target for the preview area, bucketed to avoid reload churn
    /// on small resizes, clamped to [1920, 4096].
    static func targetPixels(for size: CGSize) -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let longEdge = Int((max(size.width, size.height) * scale).rounded(.up))
        let bucketed = ((longEdge + 199) / 200) * 200
        return min(max(bucketed, 1920), 4096)
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
