import SwiftUI

/// Large preview of the selected photo with a filmstrip below.
struct LoupeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let group = app.selectedGroup {
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
        .task(id: group.id) {
            image = await ThumbnailLoader.shared.thumbnail(for: group.previewURL, maxPixel: 2560)
        }
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
                                      isSelected: group.id == app.selectedID,
                                      side: 84, showsCaption: false)
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture { app.select(group.id) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .onChange(of: app.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
