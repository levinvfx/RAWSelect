import SwiftUI

struct ThumbnailGridView: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(app.filteredGroups) { group in
                        ThumbnailCell(group: group, isSelected: group.id == app.selectedID)
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                app.select(group.id)
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                app.select(group.id)
                                app.viewMode = .loupe
                            })
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: app.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
