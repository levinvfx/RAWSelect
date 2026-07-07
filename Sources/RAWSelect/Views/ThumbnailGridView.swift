import SwiftUI

struct ThumbnailGridView: View {
    @EnvironmentObject var app: AppState

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: app.thumbnailSize, maximum: app.thumbnailSize * 1.4), spacing: 16)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(app.filteredGroups) { group in
                        ThumbnailCell(group: group,
                                      isSelected: app.selectedIDs.contains(group.id),
                                      isCurrent: group.id == app.currentID,
                                      side: app.thumbnailSize)
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
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: app.currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
