import SwiftUI

struct ThumbnailGridView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    private let spacing: CGFloat = 16
    private let outerPadding: CGFloat = 20

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: settings.thumbnailSize, maximum: settings.thumbnailSize * 1.4), spacing: spacing)]
    }

    /// Mirrors SwiftUI's adaptive-grid packing so ↑/↓ move exactly one visible row.
    private func columnCount(for width: CGFloat) -> Int {
        let available = width - outerPadding * 2
        let per = settings.thumbnailSize + spacing
        return max(1, Int((available + spacing) / per))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(app.filteredGroups) { group in
                            ThumbnailCell(group: group,
                                          isSelected: app.selectedIDs.contains(group.id),
                                          isCurrent: group.id == app.currentID,
                                          side: settings.thumbnailSize)
                                .id(group.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    app.click(group.id)
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    app.selectSingle(group.id)
                                    app.viewMode = .loupe
                                })
                        }
                    }
                    .padding(outerPadding)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .onChange(of: app.currentID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear { app.gridColumns = columnCount(for: geo.size.width) }
            .onChange(of: geo.size.width) { _, w in app.gridColumns = columnCount(for: w) }
            .onChange(of: settings.thumbnailSize) { _, _ in app.gridColumns = columnCount(for: geo.size.width) }
        }
    }
}
